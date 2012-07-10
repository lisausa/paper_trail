class Revision < ActiveRecord::Base
  belongs_to :item, :polymorphic => true
  validates_presence_of :event
  attr_accessible :item_type, :item_id, :event, :whodunnit, :object, :object_changes

  def self.with_item_keys(item_type, item_id)
    scoped(:conditions => { :item_type => item_type, :item_id => item_id.to_s })
  end

  def self.creates
    where :event => 'create'
  end

  def self.updates
    where :event => 'update'
  end

  def self.destroys
    where :event => 'destroy'
  end

  scope :subsequent, lambda { |revision|
    where(["#{self.primary_key} > ?", revision]).order("#{self.primary_key} ASC")
  }

  scope :preceding, lambda { |revision|
    where(["#{self.primary_key} < ?", revision]).order("#{self.primary_key} DESC")
  }

  scope :following, lambda { |timestamp|
    # TODO: is this :order necessary, considering its presence on the has_many :revisions association?
    where(["#{PaperTrail.timestamp_field} > ?", timestamp]).
      order("#{PaperTrail.timestamp_field} ASC, #{self.primary_key} ASC")
  }

  scope :between, lambda { |start_time, end_time|
    where(["#{PaperTrail.timestamp_field} > ? AND #{PaperTrail.timestamp_field} < ?", start_time, end_time ]).
      order("#{PaperTrail.timestamp_field} ASC, #{self.primary_key} ASC")
  }

  # Restore the item from this revision.
  #
  # This will automatically restore all :has_one associations as they were "at the time",
  # if they are also being versioned by PaperTrail.  NOTE: this isn't always guaranteed
  # to work so you can either change the lookback period (from the default 3 seconds) or
  # opt out.
  #
  # Options:
  # +:has_one+   set to `false` to opt out of has_one reification.
  #              set to a float to change the lookback time (check whether your db supports
  #              sub-second datetimes if you want them).
  def reify(options = {})
    without_identity_map do
      options[:has_one] = 3 if options[:has_one] == true
      options.reverse_merge! :has_one => false

      unless object.nil?
        attrs = YAML::load object

        # Normally a polymorphic belongs_to relationship allows us
        # to get the object we belong to by calling, in this case,
        # +item+.  However this returns nil if +item+ has been
        # destroyed, and we need to be able to retrieve destroyed
        # objects.
        #
        # In this situation we constantize the +item_type+ to get hold of
        # the class...except when the stored object's attributes
        # include a +type+ key.  If this is the case, the object
        # we belong to is using single table inheritance and the
        # +item_type+ will be the base class, not the actual subclass.
        # If +type+ is present but empty, the class is the base class.

        if item
          model = item
        else
          inheritance_column_name = item_type.constantize.inheritance_column
          class_name = attrs[inheritance_column_name].blank? ? item_type : attrs[inheritance_column_name]
          klass = class_name.constantize
          model = klass.new
        end

        attrs.each do |k, v|
          if model.respond_to?("#{k}=")
            model.send :write_attribute, k.to_sym, v
          else
            logger.warn "Attribute #{k} does not exist on #{item_type} (Revision id: #{id})."
          end
        end

        model.send "#{model.class.revision_association_name}=", self

        unless options[:has_one] == false
          reify_has_ones model, options[:has_one]
        end

        model
      end
    end
  end

  # Returns what changed in this revision of the item.  Cf. `ActiveModel::Dirty#changes`.
  # Returns nil if your `revisions` table does not have an `object_changes` text column.
  def changeset
    if self.class.column_names.include? 'object_changes'
      if changes = object_changes
        HashWithIndifferentAccess[YAML::load(changes)]
      else
        {}
      end
    end
  end

  # Returns who put the item into the state stored in this revision.
  def originator
    previous.try :whodunnit
  end

  # Returns who changed the item from the state it had in this revision.
  # This is an alias for `whodunnit`.
  def terminator
    whodunnit
  end

  def sibling_revisions
    self.class.with_item_keys(item_type, item_id)
  end

  def next
    sibling_revisions.subsequent(self).first
  end

  def previous
    sibling_revisions.preceding(self).first
  end

  def index
    id_column = self.class.primary_key.to_sym
    sibling_revisions.select(id_column).order("#{id_column} ASC").map(&id_column).index(self.send(id_column))
  end

  private

  # In Rails 3.1+, calling reify on a previous revision confuses the
  # IdentityMap, if enabled. This prevents insertion into the map.
  def without_identity_map(&block)
    if defined?(ActiveRecord::IdentityMap) && ActiveRecord::IdentityMap.respond_to?(:without)
      ActiveRecord::IdentityMap.without(&block)
    else
      block.call
    end
  end

  # Restore the `model`'s has_one associations as they were when this revision was
  # superseded by the next (because that's what the user was looking at when they
  # made the change).
  #
  # The `lookback` sets how many seconds before the model's change we go.
  def reify_has_ones(model, lookback)
    model.class.reflect_on_all_associations(:has_one).each do |assoc|
      child = model.send assoc.name
      if child.respond_to? :revision_at
        # N.B. we use revision of the child as it was `lookback` seconds before the parent was updated.
        # Ideally we want the revision of the child as it was just before the parent was updated...
        # but until PaperTrail knows which updates are "together" (e.g. parent and child being
        # updated on the same form), it's impossible to tell when the overall update started;
        # and therefore impossible to know when "just before" was.
        if (child_as_it_was = child.revision_at(send(PaperTrail.timestamp_field) - lookback.seconds))
          child_as_it_was.attributes.each do |k,v|
            model.send(assoc.name).send :write_attribute, k.to_sym, v rescue nil
          end
        else
          model.send "#{assoc.name}=", nil
        end
      end
    end
  end

end
