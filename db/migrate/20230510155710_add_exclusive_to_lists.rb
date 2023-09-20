# frozen_string_literal: true

class AddExclusiveToLists < ActiveRecord::Migration[7.0]

  def up
    add_column :lists, :exclusive, :boolean
    change_column_default :lists, :exclusive, false
  end

  def down
    remove_column :lists, :exclusive
  end
end
