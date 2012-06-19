require 'test_helper'

class RevisionTest < ActiveSupport::TestCase
  setup {
    change_schema
    @article = Animal.create
    assert Revision.creates.present?
  }

  context "Revision.creates" do
    should "return only create events" do
      Revision.creates.each do |revision|
        assert_equal "create", revision.event
      end
    end
  end

  context "Revision.updates" do
    setup {
      @article.update_attributes(:name => 'Animal')
      assert Revision.updates.present?
    }

    should "return only update events" do
      Revision.updates.each do |revision|
        assert_equal "update", revision.event
      end
    end
  end

  context "Revision.destroys" do
    setup {
      @article.destroy
      assert Revision.destroys.present?
    }

    should "return only destroy events" do
      Revision.destroys.each do |revision|
        assert_equal "destroy", revision.event
      end
    end
  end
end
