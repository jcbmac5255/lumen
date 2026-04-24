class AddUniqueIndexToCategoriesNameFamilyId < ActiveRecord::Migration[7.2]
  def change
    # Case-insensitive uniqueness on (family_id, name) — DB-level safety net
    # to catch races where two users submit the same new category name
    # simultaneously and both pass the model-level validation.
    add_index :categories, "family_id, LOWER(name)",
              unique: true,
              name: "index_categories_on_family_id_and_lower_name"
  end
end
