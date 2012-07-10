module PaperTrail
  module Model

    def self.included(base)
      base.send :extend, ClassMethods
    end


    module ClassMethods
      # Declare this in your model to track every create, update, and destroy.  Each revision of
      # the model is available in the `revisions` association.
      #
      # Options:
      # :on           the events to track (optional; defaults to all of them).  Set to an array of
      #               `:create`, `:update`, `:destroy` as desired.
      # :class_name   the name of a custom Revision class.  This class should inherit from Revision.
      # :ignore       an array of attributes for which a new `Revision` will not be created if only they change.
      # :if, :unless  Procs that allow to specify conditions when to save revisions for an object
      # :only         inverse of `ignore` - a new `Revision` will be created only for these attributes if supplied
      # :skip         fields to ignore completely.  As with `ignore`, updates to these fields will not create
      #               a new `Revision`.  In addition, these fields will not be included in the serialized revisions
      #               of the object whenever a new `Revision` is created.
      # :meta         a hash of extra data to store.  You must add a column to the `revisions` table for each key.
      #               Values are objects or procs (which are called with `self`, i.e. the model with the paper
      #               trail).  See `PaperTrail::Controller.info_for_paper_trail` for how to store data from
      #               the controller.
      # :revisions     the name to use for the revisions association.  Default is `:revisions`.
      # :revision      the name to use for the method which returns the revision the instance was reified from.
      #               Default is `:revision`.
      def has_paper_trail(options = {})
        # Lazily include the instance methods so we don't clutter up
        # any more ActiveRecord models than we have to.
        send :include, InstanceMethods

        class_attribute :revision_association_name
        self.revision_association_name = options[:revision] || :revision

        # The revision this instance was reified from.
        attr_accessor self.revision_association_name

        class_attribute :revision_class_name
        self.revision_class_name = options[:class_name] || 'Revision'

        class_attribute :ignore
        self.ignore = ([options[:ignore]].flatten.compact || []).map &:to_s

        class_attribute :if_condition
        self.if_condition = options[:if]

        class_attribute :unless_condition
        self.unless_condition = options[:unless]

        class_attribute :skip
        self.skip = ([options[:skip]].flatten.compact || []).map &:to_s

        class_attribute :only
        self.only = ([options[:only]].flatten.compact || []).map &:to_s

        class_attribute :meta
        self.meta = options[:meta] || {}

        class_attribute :paper_trail_enabled_for_model
        self.paper_trail_enabled_for_model = true

        class_attribute :revisions_association_name
        self.revisions_association_name = options[:revisions] || :revisions

        has_many self.revisions_association_name,
                 :class_name  => revision_class_name,
                 :as          => :item,
                 :primary_key => :id_as_string,
                 :order       => "#{PaperTrail.timestamp_field} ASC, #{self.revision_class_name.constantize.primary_key} ASC"

        after_create  :record_create, :if => :save_revision? if !options[:on] || options[:on].include?(:create)
        before_update :record_update, :if => :save_revision? if !options[:on] || options[:on].include?(:update)
        after_destroy :record_destroy if !options[:on] || options[:on].include?(:destroy)
      end

      # Switches PaperTrail off for this class.
      def paper_trail_off
        self.paper_trail_enabled_for_model = false
      end

      # Switches PaperTrail on for this class.
      def paper_trail_on
        self.paper_trail_enabled_for_model = true
      end
    end

    # Wrap the following methods in a module so we can include them only in the
    # ActiveRecord models that declare `has_paper_trail`.
    module InstanceMethods
      # Returns true if this instance is the current, live one;
      # returns false if this instance came from a previous revision.
      def live?
        source_revision.nil?
      end

      # Returns who put the object into its current state.
      def originator
        revision_class.with_item_keys(self.class.name, id).last.try :whodunnit
      end

      # Returns the object (not a Revision) as it was at the given timestamp.
      def revision_at(timestamp, reify_options={})
        # Because a revision stores how its object looked *before* the change,
        # we need to look for the first revision created *after* the timestamp.
        v = send(self.class.revisions_association_name).following(timestamp).first
        v ? v.reify(reify_options) : self
      end

      # Returns the objects (not Revisions) as they were between the given times.
      def revisions_between(start_time, end_time, reify_options={})
        revisions = send(self.class.revisions_association_name).between(start_time, end_time)
        revisions.collect { |revision| revision_at(revision.send PaperTrail.timestamp_field) }
      end

      # Returns the object (not a Revision) as it was most recently.
      def previous_revision
        preceding_revision = source_revision ? source_revision.previous : send(self.class.revisions_association_name).last
        preceding_revision.try :reify
      end

      # Returns the object (not a Revision) as it became next.
      def next_revision
        # NOTE: if self (the item) was not reified from a revision, i.e. it is the
        # "live" item, we return nil.  Perhaps we should return self instead?
        subsequent_revision = source_revision ? source_revision.next : nil
        subsequent_revision.reify if subsequent_revision
      end

      # Executes the given method or block without creating a new revision.
      def without_versioning(method = nil)
        paper_trail_was_enabled = self.paper_trail_enabled_for_model
        self.class.paper_trail_off
        method ? method.to_proc.call(self) : yield
      ensure
        self.class.paper_trail_on if paper_trail_was_enabled
      end
      alias :without_paper_trail :without_versioning

      # Unfortunately, this cannot be private
      def id_as_string
        self.id.to_s
      end

      private

      def revision_class
        revision_class_name.constantize
      end

      def source_revision
        send self.class.revision_association_name
      end

      def record_create
        if switched_on?
          send(self.class.revisions_association_name).create merge_metadata(:event => 'create', :whodunnit => PaperTrail.whodunnit)
        end
      end

      def record_update
        if switched_on? && changed_notably?
          data = {
            :event     => 'update',
            :object    => object_to_string(item_before_change),
            :whodunnit => PaperTrail.whodunnit
          }
          if revision_class.column_names.include? 'object_changes'
            # The double negative (reject, !include?) preserves the hash structure of self.changes.
            data[:object_changes] = self.changes.reject do |key, value|
              !notably_changed.include?(key)
            end.to_yaml
          end
          send(self.class.revisions_association_name).build merge_metadata(data)
        end
      end

      def record_destroy
        if switched_on? and not new_record?
          revision_class.create merge_metadata(:item_id   => self.id_as_string,
                                              :item_type => self.class.base_class.name,
                                              :event     => 'destroy',
                                              :object    => object_to_string(item_before_change),
                                              :whodunnit => PaperTrail.whodunnit)
        end
        send(self.class.revisions_association_name).send :load_target
      end

      def merge_metadata(data)
        # First we merge the model-level metadata in `meta`.
        meta.each do |k,v|
          data[k] =
            if v.respond_to?(:call)
              v.call(self)
            elsif v.is_a?(Symbol) && respond_to?(v)
              send(v)
            else
              v
            end
        end
        # Second we merge any extra data from the controller (if available).
        data.merge(PaperTrail.controller_info || {})
      end

      def item_before_change
        previous = self.dup
        # `dup` clears timestamps so we add them back.
        all_timestamp_attributes.each do |column|
          previous[column] = send(column) if respond_to?(column) && !send(column).nil?
        end
        previous.tap do |prev|
          prev.id = id
          changed_attributes.each { |attr, before| prev[attr] = before }
        end
      end

      def object_to_string(object)
        object.attributes.except(*self.class.skip).to_yaml
      end

      def changed_notably?
        notably_changed.any?
      end

      def notably_changed
        self.class.only.empty? ? changed_and_not_ignored : (changed_and_not_ignored & self.class.only)
      end

      def changed_and_not_ignored
        changed - self.class.ignore - self.class.skip
      end

      def switched_on?
        PaperTrail.enabled? && PaperTrail.enabled_for_controller? && self.class.paper_trail_enabled_for_model
      end

      def save_revision?
        (if_condition.blank? || if_condition.call(self)) && !unless_condition.try(:call, self)
      end
    end
  end
end
