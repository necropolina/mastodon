class AddNotNullToExclusiveLists < ActiveRecord::Migration[7.0]

  def up
    change_column_null :lists, :exclusive, false
  end
end
