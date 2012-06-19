class LegacyWidget < ActiveRecord::Base
  has_paper_trail :ignore  => :revision,
                  :revision => 'custom_revision'
end
