class AddNotNullToExclusiveLists < ActiveRecord::Migration[7.0]
  def change
    add_check_constraint :lists, "exclusive IS NOT NULL", name: "lists_exclusive_null", validate: false
  end
end
