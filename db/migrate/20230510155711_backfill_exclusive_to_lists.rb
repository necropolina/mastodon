
class BackfillExclusiveToLists < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    List.unscoped.in_batches do |relation|
      relation.update_all exclusive: false
      sleep(0.01)
    end
  end
end
