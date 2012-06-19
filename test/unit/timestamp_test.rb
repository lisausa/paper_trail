require 'test_helper'

class TimestampTest < ActiveSupport::TestCase

  setup do
    PaperTrail.timestamp_field = :custom_created_at
    change_schema
    Revision.reset_column_information

    Fluxor.instance_eval <<-END
      has_paper_trail
    END

    @fluxor = Fluxor.create :name => 'Some text.'
    @fluxor.update_attributes :name => 'Some more text.'
    @fluxor.update_attributes :name => 'Even more text.'
  end

  teardown do
    PaperTrail.timestamp_field = :created_at
  end

  test 'revisions works with custom timestamp field' do
    # Normal behaviour
    assert_equal 3, @fluxor.revisions.length
    assert_nil @fluxor.revisions[0].reify
    assert_equal 'Some text.', @fluxor.revisions[1].reify.name
    assert_equal 'Some more text.', @fluxor.revisions[2].reify.name

    # Tinker with custom timestamps.
    now = Time.now.utc
    @fluxor.revisions.reverse.each_with_index do |revision, index|
      revision.update_attribute :custom_created_at, (now + index.seconds)
    end

    # Test we are ordering by custom timestamps.
    @fluxor.revisions true  # reload association
    assert_nil @fluxor.revisions[2].reify
    assert_equal 'Some text.', @fluxor.revisions[1].reify.name
    assert_equal 'Some more text.', @fluxor.revisions[0].reify.name
  end

end
