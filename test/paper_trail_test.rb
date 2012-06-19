require 'test_helper'

class PaperTrailTest < ActiveSupport::TestCase
  test 'Sanity test' do
    assert_kind_of Module, PaperTrail
  end

  test 'create with plain model class' do
    widget = Widget.create
    assert_equal 1, widget.revisions.length
  end

  test 'update with plain model class' do
    widget = Widget.create
    assert_equal 1, widget.revisions.length
    widget.update_attributes(:name => 'Bugle')
    assert_equal 2, widget.revisions.length
  end

  test 'destroy with plain model class' do
    widget = Widget.create
    assert_equal 1, widget.revisions.length
    widget.destroy
    revisions_for_widget = Revision.with_item_keys('Widget', widget.id)
    assert_equal 2, revisions_for_widget.length
  end
end
