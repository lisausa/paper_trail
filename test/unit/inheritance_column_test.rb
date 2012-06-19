require 'test_helper'

class InheritanceColumnTest < ActiveSupport::TestCase

  context 'STI models' do
    setup do
      @animal = Animal.create :name => 'Animal'
      @animal.update_attributes :name => 'Animal from the Muppets'
      @animal.update_attributes :name => 'Animal Muppet'
      @animal.destroy

      @dog = Dog.create :name => 'Snoopy'
      @dog.update_attributes :name => 'Scooby'
      @dog.update_attributes :name => 'Scooby Doo'
      @dog.destroy

      @cat = Cat.create :name => 'Garfield'
      @cat.update_attributes :name => 'Garfield (I hate Mondays)'
      @cat.update_attributes :name => 'Garfield The Cat'
      @cat.destroy
    end

    should 'work with custom STI inheritance column' do
      assert_equal 12, Revision.count
      assert_equal 4, @animal.revisions.count
      assert @animal.revisions.first.reify.nil?
      @animal.revisions[1..-1].each { |v| assert_equal 'Animal', v.reify.class.name }

      # For some reason `@dog.revisions` doesn't include the final `destroy` revision.
      # Neither do `@dog.revisions.scoped` nor `@dog.revisions(true)` nor `@dog.revisions.reload`.
      dog_revisions = Revision.where(:item_id => @dog.id)
      assert_equal 4, dog_revisions.count
      assert dog_revisions.first.reify.nil?
      dog_revisions[1..-1].each { |v| assert_equal 'Dog', v.reify.class.name }

      cat_revisions = Revision.where(:item_id => @cat.id)
      assert_equal 4, cat_revisions.count
      assert cat_revisions.first.reify.nil?
      cat_revisions[1..-1].each { |v| assert_equal 'Cat', v.reify.class.name }
    end
  end

end
