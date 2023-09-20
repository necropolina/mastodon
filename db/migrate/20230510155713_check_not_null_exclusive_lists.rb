class CheckNotNullExclusiveLists < ActiveRecord::Migration[7.0]
  def change
    validate_check_constraint :lists, name: "lists_exclusive_null"
  end
end
