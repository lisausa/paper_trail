class AddObjectChangesColumnToRevisions < ActiveRecord::Migration
  def self.up
    add_column :revisions, :object_changes, :text
  end

  def self.down
    remove_column :revisions, :object_changes
  end
end
