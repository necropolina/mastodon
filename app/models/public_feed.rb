# frozen_string_literal: true

class PublicFeed
  # number of days ahead to look when filtering boosts
  FILTER_REBLOGS_N_DAYS_AHEAD = 1.day

  # @param [Account] account
  # @param [Hash] options
  # @option [Boolean] :with_replies
  # @option [Boolean] :with_reblogs
  # @option [Boolean] :local
  # @option [Boolean] :remote
  # @option [Boolean] :only_media
  # @option [Boolean] :allow_local_only
  def initialize(account, options = {})
    @account = account
    @options = options
  end

  # @param [Integer] limit
  # @param [Integer] max_id
  # @param [Integer] since_id
  # @param [Integer] min_id
  # @return [Array<Status>]
  def get(limit, max_id = nil, since_id = nil, min_id = nil)
    scope = public_scope

    scope.merge!(without_local_only_scope) unless allow_local_only?
    scope.merge!(without_replies_scope) unless with_replies?
    scope.merge!(without_reblogs_scope) unless with_reblogs?
    scope.merge!(without_duplicate_reblogs(limit, max_id, since_id, min_id)) if with_reblogs?
    scope.merge!(local_only_scope) if local_only?
    scope.merge!(remote_only_scope) if remote_only?
    scope.merge!(account_filters_scope) if account?
    scope.merge!(media_only_scope) if media_only?
    scope.merge!(language_scope) if account&.chosen_languages.present?

    scope.cache_ids.to_a_paginated_by_id(limit, max_id: max_id, since_id: since_id, min_id: min_id)
  end

  private

  attr_reader :account, :options

  def allow_local_only?
    local_account? && (local_only? || options[:allow_local_only])
  end

  def with_reblogs?
    options[:with_reblogs]
  end

  def with_replies?
    options[:with_replies]
  end

  def local_only?
    options[:local] && !options[:remote]
  end

  def remote_only?
    options[:remote] && !options[:local]
  end

  def account?
    account.present?
  end

  def local_account?
    account&.local?
  end

  def media_only?
    options[:only_media]
  end

  def public_scope
    Status.with_public_visibility.joins(:account).merge(Account.without_suspended.without_silenced)
  end

  def local_only_scope
    Status.local
  end

  def remote_only_scope
    Status.remote
  end

  def without_replies_scope
    Status.without_replies
  end

  def without_reblogs_scope
    Status.without_reblogs
  end

  def without_duplicate_reblogs(limit, max_id, _since_id, min_id)
    # See https://wiki.neuromatch.social/Filter_Duplicate_Boosts
    # General strategy: for a given page of results, we care about whether
    # a post that has been boosted in this page has also been boosted more recently.
    # ie. for filtering, we care about all the posts in the future, but none in the past.
    #
    # we have three nested queries that are roughly:
    # - regular (non-boost posts) OR
    # - boosts IN
    #   - most recent boost per original post IN
    #     - boosts made from now until n days in the future

    # First get limited statuses that could contain boosts
    # Get this first so the later DISTINCT ON term's need for ordering by reblog_of_id
    # doesn't cause us to be filtering over the wrong statuses
    candidate_statuses = Status.select(:id).reorder(id: :desc)

    # Set lower bound
    candidate_statuses = if min_id.present?
                           # we don't want to reorder id ascending here like the outer min_id param does -
                           # in this inner query, we want to only show the latest boost, and so the order
                           # needs to be descending. in both cases, we want to evaluate many more statuses into the future
                           # than the outer query, which provides this option to use like min_id + limit
                           candidate_statuses.where(Status.arel_table[:id].gt(min_id))
                         elsif max_id.present?
                           # Since_id is only relevant as a limit when there are fewer than `limit` posts between max_id
                           # and since_id, so we don't use it here. We can't just use `limit` unless we don't have a max_id, which
                           # means we are only getting the most recent statuses. Otherwise, we need to get some arbitrary number
                           # of statuses in the future to check for boosts. To set some lower bound on that, we use the limit + max_id
                           # to get the nth post after the max_id as the lower bound.
                           candidate_statuses.where(<<~SQL.squish, max_id: max_id.to_i, limit: limit)
                             "statuses"."id" > (
                               SELECT LAG(id,:limit) OVER (
                                 ORDER BY id DESC
                               ) FROM statuses
                               WHERE id = :max_id
                             )
                           SQL
                         else
                           candidate_statuses.limit(limit)
                         end

    if min_id.present?
      # the only time a missing max_id is a problem is when we are doing reverse pagination, ie. with
      # min_id, so in that case we set the max_id relative to that.
      # Check this before max_id, since if a min_id is present max_id is not limiting
      max_time = Mastodon::Snowflake.to_time(min_id.to_i)
      max_time += FILTER_REBLOGS_N_DAYS_AHEAD
      max_id = Mastodon::Snowflake.id_at(max_time)
      candidate_statuses = candidate_statuses.where(Status.arel_table[:id].lt(max_id))
    elsif max_id.present?
      # We don't want to use the given max_id since that will cause boosts to repeat
      # across pages. Instead, if we're provided one, we increase it by some window of future posts to consider -
      # so ok if people are boosting the same post a lot and there are fewer than 20 posts
      # in a day, you'll see duplicates.
      max_time = Mastodon::Snowflake.to_time(max_id.to_i)
      max_time += FILTER_REBLOGS_N_DAYS_AHEAD
      max_id = Mastodon::Snowflake.id_at(max_time)
      candidate_statuses = candidate_statuses.where(Status.arel_table[:id].lt(max_id))
    end

    inner_query = Status
                  .where(id: candidate_statuses)
                  .select('DISTINCT ON (reblog_of_id) statuses.id')
                  .reorder(reblog_of_id: :desc, id: :desc)

    Status.where(statuses: { reblog_of_id: nil })
          .or(Status.where(id: inner_query))
  end

  def media_only_scope
    Status.joins(:media_attachments).group(:id)
  end

  def without_local_only_scope
    Status.not_local_only
  end

  def language_scope
    Status.where(language: account.chosen_languages)
  end

  def account_filters_scope
    Status.not_excluded_by_account(account).tap do |scope|
      scope.merge!(Status.not_domain_blocked_by_account(account)) unless local_only?
    end
  end
end
