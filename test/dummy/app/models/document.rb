class Document < ActiveRecord::Base
  has_paper_trail :revisions => :paper_trail_revisions,
                  :on => [:create, :update]
end
