# PaperTrail [![Dependency Status](https://gemnasium.com/lisausa/paper_trail.png)](https://gemnasium.com/lisausa/paper_trail)

PaperTrail lets you track changes to your models' data.  It's good for auditing or revisioning.  You can see how a model looked at any stage in its lifecycle, revert it to any revision, and even undelete it after it's been destroyed.

There's an excellent [Railscast on implementing Undo with Paper Trail](http://railscasts.com/episodes/255-undo-with-paper-trail).


## Features

* Stores every create, update and destroy (or only the lifecycle events you specify).
* Does not store updates which don't change anything.
* Allows you to specify attributes (by inclusion or exclusion) which must change for a Revision to be stored.
* Allows you to get at every revision, including the original, even once destroyed.
* Allows you to get at every revision even if the schema has since changed.
* Allows you to get at the revision as of a particular time.
* Option to automatically restore `has_one` associations as they were at the time.
* Automatically records who was responsible via your controller.  PaperTrail calls `current_user` by default, if it exists, but you can have it call any method you like.
* Allows you to set who is responsible at model-level (useful for migrations).
* Allows you to store arbitrary model-level metadata with each revision (useful for filtering revisions).
* Allows you to store arbitrary controller-level information with each revision, e.g. remote IP.
* Can be turned off/on per class (useful for migrations).
* Can be turned off/on per request (useful for testing with an external service).
* Can be turned off/on globally (useful for testing).
* No configuration necessary.
* Stores everything in a single database table by default (generates migration for you), or can use separate tables for separate models.
* Supports custom revision classes so different models' revisions can have different behaviour.
* Supports custom name for revisions association.
* Thoroughly tested.
* Threadsafe.


## Rails Version

Works on Rails 3 and Rails 2.3.  The Rails 3 code is on the `master` branch and tagged `v2.x`.  The Rails 2.3 code is on the `rails2` branch and tagged `v1.x`.  Please note I'm not adding new features to the Rails 2.3 codebase.


## API Summary

When you declare `has_paper_trail` in your model, you get these methods:

    class Widget < ActiveRecord::Base
      has_paper_trail   # you can pass various options here
    end

    # Returns this widget's revisions.  You can customise the name of the association.
    widget.revisions

    # Return the revision this widget was reified from, or nil if it is live.
    # You can customise the name of the method.
    widget.revision

    # Returns true if this widget is the current, live one; or false if it is from a previous revision.
    widget.live?

    # Returns who put the widget into its current state.
    widget.originator

    # Returns the widget (not a revision) as it looked at the given timestamp.
    widget.revision_at(timestamp)

    # Returns the widget (not a revision) as it was most recently.
    widget.previous_revision

    # Returns the widget (not a revision) as it became next.
    widget.next_revision

    # Turn PaperTrail off for all widgets.
    Widget.paper_trail_off

    # Turn PaperTrail on for all widgets.
    Widget.paper_trail_on

And a `Revision` instance has these methods:

    # Returns the item restored from this revision.
    revision.reify(options = {})

    # Returns who put the item into the state stored in this revision.
    revision.originator

    # Returns who changed the item from the state it had in this revision.
    revision.terminator
    revision.whodunnit

    # Returns the next revision.
    revision.next

    # Returns the previous revision.
    revision.previous

    # Returns the index of this revision in all the revisions.
    revision.index

    # Returns the event that caused this revision (create|update|destroy).
    revision.event

In your controllers you can override these methods:

    # Returns the user who is responsible for any changes that occur.
    # Defaults to current_user.
    user_for_paper_trail

    # Returns any information about the controller or request that you want
    # PaperTrail to store alongside any changes that occur.
    info_for_paper_trail


## Basic Usage

PaperTrail is simple to use.  Just add 15 characters to a model to get a paper trail of every `create`, `update`, and `destroy`.

    class Widget < ActiveRecord::Base
      has_paper_trail
    end

This gives you a `revisions` method which returns the paper trail of changes to your model.

    >> widget = Widget.find 42
    >> widget.revisions             # [<Revision>, <Revision>, ...]

Once you have a revision, you can find out what happened:

    >> v = widget.revisions.last
    >> v.event                     # 'update' (or 'create' or 'destroy')
    >> v.whodunnit                 # '153'  (if the update was via a controller and
                                   #         the controller has a current_user method,
                                   #         here returning the id of the current user)
    >> v.created_at                # when the update occurred
    >> widget = v.reify            # the widget as it was before the update;
                                   # would be nil for a create event

PaperTrail stores the pre-change revision of the model, unlike some other auditing/versioning plugins, so you can retrieve the original revision.  This is useful when you start keeping a paper trail for models that already have records in the database.

    >> widget = Widget.find 153
    >> widget.name                                 # 'Doobly'

    # Add has_paper_trail to Widget model.

    >> widget.revisions                             # []
    >> widget.update_attributes :name => 'Wotsit'
    >> widget.revisions.first.reify.name            # 'Doobly'
    >> widget.revisions.first.event                 # 'update'

This also means that PaperTrail does not waste space storing a revision of the object as it currently stands.  The `revisions` method gives you previous revisions; to get the current one just call a finder on your `Widget` model as usual.

Here's a helpful table showing what PaperTrail stores:

<table>
  <tr>
    <th>Event</th>
    <th>Model Before</th>
    <th>Model After</th>
  </tr>
  <tr>
    <td>create</td>
    <td>nil</td>
    <td>widget</td>
  </tr>
  <tr>
    <td>update</td>
    <td>widget</td>
    <td>widget'</td>
  <tr>
    <td>destroy</td>
    <td>widget</td>
    <td>nil</td>
  </tr>
</table>

PaperTrail stores the values in the Model Before column.  Most other auditing/versioning plugins store the After column.


## Choosing Lifecycle Events To Monitor

You can choose which events to track with the `on` option.  For example, to ignore `create` events:

    class Article < ActiveRecord::Base
      has_paper_trail :on => [:update, :destroy]
    end


## Choosing When To Save New Revisions

You can choose the conditions when to add new revisions with the `if` and `unless` options. For example, to save revisions only for US non-draft translations:

    class Translation < ActiveRecord::Base
      has_paper_trail :if     => Proc.new { |t| t.language_code == 'US' },
                      :unless => Proc.new { |t| t.type == 'DRAFT'       }
    end



## Choosing Attributes To Monitor

You can ignore changes to certain attributes like this:

    class Article < ActiveRecord::Base
      has_paper_trail :ignore => [:title, :rating]
    end

This means that changes to just the `title` or `rating` will not store another revision of the article.  It does not mean that the `title` and `rating` attributes will be ignored if some other change causes a new `Revision` to be created.  For example:

    >> a = Article.create
    >> a.revisions.length                         # 1
    >> a.update_attributes :title => 'My Title', :rating => 3
    >> a.revisions.length                         # 1
    >> a.update_attributes :content => 'Hello'
    >> a.revisions.length                         # 2
    >> a.revisions.last.reify.title               # 'My Title'

Or, you can specify a list of all attributes you care about:

    class Article < ActiveRecord::Base
      has_paper_trail :only => [:title]
    end

This means that only changes to the `title` will save a revision of the article:

    >> a = Article.create
    >> a.revisions.length                         # 1
    >> a.update_attributes :title => 'My Title'
    >> a.revisions.length                         # 2
    >> a.update_attributes :content => 'Hello'
    >> a.revisions.length                         # 2

Passing both `:ignore` and `:only` options will result in the article being saved if a changed attribute is included in `:only` but not in `:ignore`.

You can skip fields altogether with the `:skip` option.  As with `:ignore`, updates to these fields will not create a new `Revision`.  In addition, these fields will not be included in the serialised revision of the object whenever a new `Revision` is created.

For example:

    class Article < ActiveRecord::Base
      has_paper_trail :skip => [:file_upload]
    end


## Reverting And Undeleting A Model

PaperTrail makes reverting to a previous revision easy:

    >> widget = Widget.find 42
    >> widget.update_attributes :name => 'Blah blah'
    # Time passes....
    >> widget = widget.revisions.last.reify  # the widget as it was before the update
    >> widget.save                          # reverted

Alternatively you can find the revision at a given time:

    >> widget = widget.revision_at(1.day.ago)  # the widget as it was one day ago
    >> widget.save                            # reverted

Note `revision_at` gives you the object, not a revision, so you don't need to call `reify`.

Undeleting is just as simple:

    >> widget = Widget.find 42
    >> widget.destroy
    # Time passes....
    >> widget = Revision.find(153).reify    # the widget as it was before it was destroyed
    >> widget.save                         # the widget lives!

In fact you could use PaperTrail to implement an undo system, though I haven't had the opportunity yet to do it myself.  However [Ryan Bates has](http://railscasts.com/episodes/255-undo-with-paper-trail)!


## Navigating Revisions

You can call `previous_revision` and `next_revision` on an item to get it as it was/became.  Note that these methods reify the item for you.

    >> widget = Widget.find 42
    >> widget.revisions.length              # 4 for example
    >> widget = widget.previous_revision    # => widget == widget.revisions.last.reify
    >> widget = widget.previous_revision    # => widget == widget.revisions[-2].reify
    >> widget.next_revision                 # => widget == widget.revisions.last.reify
    >> widget.next_revision                 # nil

As an aside, I'm undecided about whether `widget.revisions.last.next_revision` should return `nil` or `self` (i.e. `widget`).  Let me know if you have a view.

If instead you have a particular `revision` of an item you can navigate to the previous and next revisions.

    >> widget = Widget.find 42
    >> revision = widget.revisions[-2]    # assuming widget has several revisions
    >> previous = revision.previous
    >> next = revision.next

You can find out which of an item's revisions yours is:

    >> current_revision_number = revision.index    # 0-based

Finally, if you got an item by reifying one of its revisions, you can navigate back to the revision it came from:

    >> latest_revision = Widget.find(42).revisions.last
    >> widget = latest_revision.reify
    >> widget.revision == latest_revision    # true

You can find out whether a model instance is the current, live one -- or whether it came instead from a previous revision -- with `live?`:

    >> widget = Widget.find 42
    >> widget.live?                        # true
    >> widget = widget.revisions.last.reify
    >> widget.live?                        # false


## Finding Out Who Was Responsible For A Change

If your `ApplicationController` has a `current_user` method, PaperTrail will store the value it returns in the `revision`'s `whodunnit` column.  Note that this column is a string so you will have to convert it to an integer if it's an id and you want to look up the user later on:

    >> last_change = Widget.revisions.last
    >> user_who_made_the_change = User.find last_change.whodunnit.to_i

You may want PaperTrail to call a different method to find out who is responsible.  To do so, override the `user_for_paper_trail` method in your controller like this:

    class ApplicationController
      def user_for_paper_trail
        logged_in? ? current_member : 'Public user'  # or whatever
      end
    end

In a migration or in `script/console` you can set who is responsible like this:

    >> PaperTrail.whodunnit = 'Andy Stewart'
    >> widget.update_attributes :name => 'Wibble'
    >> widget.revisions.last.whodunnit              # Andy Stewart

N.B. A `revision`'s `whodunnit` records who changed the object causing the `revision` to be stored.  Because a `revision` stores the object as it looked before the change (see the table above), `whodunnit` returns who stopped the object looking like this -- not who made it look like this.  Hence `whodunnit` is aliased as `terminator`.

To find out who made a `revision`'s object look that way, use `revision.originator`.  And to find out who made a "live" object look like it does, use `originator` on the object.

    >> widget = Widget.find 153                    # assume widget has 0 revisions
    >> PaperTrail.whodunnit = 'Alice'
    >> widget.update_attributes :name => 'Yankee'
    >> widget.originator                           # 'Alice'
    >> PaperTrail.whodunnit = 'Bob'
    >> widget.update_attributes :name => 'Zulu'
    >> widget.originator                           # 'Bob'
    >> first_revision, last_revision = widget.revisions.first, widget.revisions.last
    >> first_revision.whodunnit                     # 'Alice'
    >> first_revision.originator                    # nil
    >> first_revision.terminator                    # 'Alice'
    >> last_revision.whodunnit                      # 'Bob'
    >> last_revision.originator                     # 'Alice'
    >> last_revision.terminator                     # 'Bob'


## Custom Revision Classes

You can specify custom revision subclasses with the `:class_name` option:

    class PostRevision < Revision
      # custom behaviour, e.g:
      self.table_name = :post_revisions
    end

    class Post < ActiveRecord::Base
      has_paper_trail :class_name => 'PostRevision'
    end

This allows you to store each model's revisions in a separate table, which is useful if you have a lot of revisions being created.

If you are using Postgres, you should also define the sequence that your custom revision class will use:

    class PostRevision < Revision
      self.table_name = :post_revisions
      self.sequence_name = :post_revision_id_seq
    end

Alternatively you could store certain metadata for one type of revision, and other metadata for other revisions.

If you only use custom revision classes and don't use PaperTrail's built-in one, on Rails 3.2 you must:

- either declare PaperTrail's revision class abstract like this (in `config/initializers/paper_trail_patch.rb`):

        Revision.module_eval do
          self.abstract_class = true
        end

- or define a `revisions` table in the database so Rails can instantiate the revision superclass.

You can also specify custom names for the revisions and revision associations.  This is useful if you already have `revisions` or/and `revision` methods on your model.  For example:

    class Post < ActiveRecord::Base
      has_paper_trail :revisions => :paper_trail_revisions,
                      :revision  => :paper_trail_revision

      # Existing revisions method.  We don't want to clash.
      def revisions
        ...
      end
      # Existing revision method.  We don't want to clash.
      def revision
        ...
      end
    end


## Associations

I haven't yet found a good way to get PaperTrail to automatically restore associations when you reify a model.  See [here for a little more info](http://airbladesoftware.com/notes/undo-and-redo-with-papertrail).

If you can think of a good way to achieve this, please let me know.


## Has-One Associations

PaperTrail can restore `:has_one` associations as they were at (actually, 3 seconds before) the time.

    class Treasure < ActiveRecord::Base
      has_one :location
    end

    >> treasure.amount                  # 100
    >> treasure.location.latitude       # 12.345

    >> treasure.update_attributes :amount => 153
    >> treasure.location.update_attributes :latitude => 54.321

    >> t = treasure.revisions.last.reify(:has_one => true)
    >> t.amount                         # 100
    >> t.location.latitude              # 12.345

The implementation is complicated by the edge case where the parent and child are updated in one go, e.g. in one web request or database transaction.  PaperTrail doesn't know about different models being updated "together", so you can't ask it definitively to get the child as it was before the joint parent-and-child update.

The correct solution is to make PaperTrail aware of requests or transactions (c.f. [Efficiency's transaction ID middleware](http://github.com/efficiency20/ops_middleware/blob/master/lib/e20/ops/middleware/transaction_id_middleware.rb)).  In the meantime we work around the problem by finding the child as it was a few seconds before the parent was updated.  By default we go 3 seconds before but you can change this by passing the desired number of seconds to the `:has_one` option:

    >> t = treasure.revisions.last.reify(:has_one => 1)       # look back 1 second instead of 3

If you are shuddering, take solace from knowing PaperTrail opts out of these shenanigans by default. This means your `:has_one` associated objects will be the live ones, not the ones the user saw at the time.  Since PaperTrail doesn't auto-restore `:has_many` associations (I can't get it to work) or `:belongs_to` (I ran out of time looking at `:has_many`), this at least makes your associations wrong consistently ;)



## Has-Many-Through Associations

PaperTrail can track most changes to the join table.  Specifically it can track all additions but it can only track removals which fire the `after_destroy` callback on the join table.  Here are some examples:

Given these models:

    class Book < ActiveRecord::Base
      has_many :authorships, :dependent => :destroy
      has_many :authors, :through => :authorships, :source => :person
      has_paper_trail
    end

    class Authorship < ActiveRecord::Base
      belongs_to :book
      belongs_to :person
      has_paper_trail      # NOTE
    end

    class Person < ActiveRecord::Base
      has_many :authorships, :dependent => :destroy
      has_many :books, :through => :authorships
      has_paper_trail
    end

Then each of the following will store authorship revisions:

    >> @book.authors << @dostoyevsky
    >> @book.authors.create :name => 'Tolstoy'
    >> @book.authorships.last.destroy
    >> @book.authorships.clear

But none of these will:

    >> @book.authors.delete @tolstoy
    >> @book.author_ids = [@solzhenistyn.id, @dostoyevsky.id]
    >> @book.authors = []

Having said that, you can apparently get all these working (I haven't tested it myself) with this patch:

    # In config/initializers/active_record_patch.rb
    module ActiveRecord
      # = Active Record Has Many Through Association
      module Associations
        class HasManyThroughAssociation < HasManyAssociation #:nodoc:
          alias_method :original_delete_records, :delete_records

          def delete_records(records, method)
            method ||= :destroy
            original_delete_records(records, method)
          end
        end
      end
    end

See [issue 113](https://github.com/airblade/paper_trail/issues/113) for a discussion about this.

There may be a way to store authorship revisions, probably using association callbacks, no matter how the collection is manipulated but I haven't found it yet.  Let me know if you do.


## Storing metadata

You can store arbitrary model-level metadata alongside each revision like this:

    class Article < ActiveRecord::Base
      belongs_to :author
      has_paper_trail :meta => { :author_id  => Proc.new { |article| article.author_id },
                                 :word_count => :count_words,
                                 :answer     => 42 }
      def count_words
        153
      end
    end

PaperTrail will call your proc with the current article and store the result in the `author_id` column of the `revisions` table.

N.B.  You must also:

* Add your metadata columns to the `revisions` table.
* Declare your metadata columns using `attr_accessible`.

For example:

    # config/initializers/paper_trail.rb
    class Revision < ActiveRecord::Base
      attr_accessible :author_id, :word_count, :answer
    end

Why would you do this?  In this example, `author_id` is an attribute of `Article` and PaperTrail will store it anyway in serialized (YAML) form in the `object` column of the `revision` record.  But let's say you wanted to pull out all revisions for a particular author; without the metadata you would have to deserialize (reify) each `revision` object to see if belonged to the author in question.  Clearly this is inefficient.  Using the metadata you can find just those revisions you want:

    Revision.all(:conditions => ['author_id = ?', author_id])

Note you can pass a symbol as a value in the `meta` hash to signal a method to call.

You can also store any information you like from your controller.  Just override the `info_for_paper_trail` method in your controller to return a hash whose keys correspond to columns in your `revisions` table.  E.g.:

    class ApplicationController
      def info_for_paper_trail
        { :ip => request.remote_ip, :user_agent => request.user_agent }
      end
    end

Remember to add those extra columns to your `revisions` table and use `attr_accessible` ;)


## Diffing Revisions

There are two scenarios: diffing adjacent revisions and diffing non-adjacent revisions.

The best way to diff adjacent revisions is to get PaperTrail to do it for you.  If you add an `object_changes` text column to your `revisions` table, either at installation time with the `--with-changes` option or manually, PaperTrail will store the `changes` diff (excluding any attributes PaperTrail is ignoring) in each `update` revision.  You can use the `revision.changeset` method to retrieve it.  For example:

    >> widget = Widget.create :name => 'Bob'
    >> widget.revisions.last.changeset                # {}
    >> widget.update_attributes :name => 'Robert'
    >> widget.revisions.last.changeset                # {'name' => ['Bob', 'Robert']}

Note PaperTrail only stores the changes for updates; there's no point storing them for created or destroyed objects.

Please be aware that PaperTrail doesn't use diffs internally.  When I designed PaperTrail I wanted simplicity and robustness so I decided to make each revision of an object self-contained.  A revision stores all of its object's data, not a diff from the previous revision.  This means you can delete any revision without affecting any other.

To diff non-adjacent revisions you'll have to write your own code.  These libraries may help:

For diffing two strings:

* [htmldiff](http://github.com/myobie/htmldiff): expects but doesn't require HTML input and produces HTML output.  Works very well but slows down significantly on large (e.g. 5,000 word) inputs.
* [differ](http://github.com/pvande/differ): expects plain text input and produces plain text/coloured/HTML/any output.  Can do character-wise, word-wise, line-wise, or arbitrary-boundary-string-wise diffs.  Works very well on non-HTML input.
* [diff-lcs](http://github.com/halostatue/ruwiki/tree/master/diff-lcs/trunk): old-school, line-wise diffs.

For diffing two ActiveRecord objects:

* [Jeremy Weiskotten's PaperTrail fork](http://github.com/jeremyw/paper_trail/blob/master/lib/paper_trail/has_paper_trail.rb#L151-156): uses ActiveSupport's diff to return an array of hashes of the changes.
* [activerecord-diff](http://github.com/tim/activerecord-diff): rather like ActiveRecord::Dirty but also allows you to specify which columns to compare.


## Turning PaperTrail Off/On

Sometimes you don't want to store changes.  Perhaps you are only interested in changes made by your users and don't need to store changes you make yourself in, say, a migration -- or when testing your application.

You can turn PaperTrail on or off in three ways: globally, per request, or per class.

### Globally

On a global level you can turn PaperTrail off like this:

    >> PaperTrail.enabled = false

For example, you might want to disable PaperTrail in your Rails application's test environment to speed up your tests.  This will do it:

    # in config/environments/test.rb
    config.after_initialize do
      PaperTrail.enabled = false
    end

If you disable PaperTrail in your test environment but want to enable it for specific tests, you can add a helper like this to your test helper:

    # in test/test_helper.rb
    def with_revisioning
      was_enabled = PaperTrail.enabled?
      PaperTrail.enabled = true
      begin
        yield
      ensure
        PaperTrail.enabled = was_enabled
      end
    end

And then use it in your tests like this:

    test "something that needs revisioning" do
      with_revisioning do
        # your test
      end
    end

### Per request

You can turn PaperTrail on or off per request by adding a `paper_trail_enabled_for_controller` method to your controller which returns true or false:

    class ApplicationController < ActionController::Base
      def paper_trail_enabled_for_controller
        request.user_agent != 'Disable User-Agent'
      end
    end

### Per class

If you are about change some widgets and you don't want a paper trail of your changes, you can turn PaperTrail off like this:

    >> Widget.paper_trail_off

And on again like this:

    >> Widget.paper_trail_on

### Per method call

You can call a method without creating a new revision using `without_revisioning`.  It takes either a method name as a symbol:

    @widget.without_revisioning :destroy

Or a block:

    @widget.without_revisioning do
      @widget.update_attributes :name => 'Ford'
    end


## Deleting Old Revisions

Over time your `revisions` table will grow to an unwieldy size.  Because each revision is self-contained (see the Diffing section above for more) you can simply delete any records you don't want any more.  For example:

    sql> delete from revisions where created_at < 2010-06-01;

    >> Revision.delete_all ["created_at < ?", 1.week.ago]


## Installation

### Rails 3

1. Install PaperTrail as a gem via your `Gemfile`:

    `gem 'paper_trail', '~> 2'`

2. Generate a migration which will add a `revisions` table to your database.

    `bundle exec rails generate paper_trail:install`

3. Run the migration.

    `bundle exec rake db:migrate`

4. Add `has_paper_trail` to the models you want to track.

### Rails 2

Please see the `rails2` branch.


## Testing

PaperTrail uses Bundler to manage its dependencies (in development and testing).  You can run the tests with `bundle exec rake test`.  (You may need to `bundle install` first.)

It's a good idea to reset PaperTrail before each test so data from one test doesn't spill over another.  For example:

    RSpec.configure do |config|
      config.before :each do
        PaperTrail.controller_info = {}
        PaperTrail.whodunnit = nil
      end
    end

You may want to turn PaperTrail off to speed up your tests.  See the "Turning PaperTrail Off/On" section above.


## Articles

[Keep a Paper Trail with PaperTrail](http://www.linux-mag.com/id/7528), Linux Magazine, 16th September 2009.


## Problems

Please use GitHub's [issue tracker](http://github.com/airblade/paper_trail/issues).


## Contributors

Many thanks to:

* [Zachery Hostens](http://github.com/zacheryph)
* [Jeremy Weiskotten](http://github.com/jeremyw)
* [Phan Le](http://github.com/revo)
* [jdrucza](http://github.com/jdrucza)
* [conickal](http://github.com/conickal)
* [Thibaud Guillaume-Gentil](http://github.com/thibaudgg)
* Danny Trelogan
* [Mikl Kurkov](http://github.com/mkurkov)
* [Franco Catena](https://github.com/francocatena)
* [Emmanuel Gomez](https://github.com/emmanuel)
* [Matthew MacLeod](https://github.com/mattmacleod)
* [benzittlau](https://github.com/benzittlau)
* [Tom Derks](https://github.com/EgoH)
* [Jonas Hoglund](https://github.com/jhoglund)
* [Stefan Huber](https://github.com/MSNexploder)
* [thinkcast](https://github.com/thinkcast)
* [Dominik Sander](https://github.com/dsander)
* [Burke Libbey](https://github.com/burke)
* [6twenty](https://github.com/6twenty)
* [nir0](https://github.com/nir0)
* [Eduard Tsech](https://github.com/edtsech)
* [Mathieu Arnold](https://github.com/mat813)
* [Nicholas Thrower](https://github.com/throwern)
* [Benjamin Curtis](https://github.com/stympy)
* [Peter Harkins](https://github.com/pushcx)
* [Mohd Amree](https://github.com/amree)
* [Nikita Cernovs](https://github.com/nikitachernov)
* [Jason Noble](https://github.com/jasonnoble)
* [Jared Mehle](https://github.com/jrmehle)
* [Eric Schwartz](https://github.com/emschwar)
* [Ben Woosley](https://github.com/Empact)
* [Philip Arndt](https://github.com/parndt)
* [Daniel Vydra](https://github.com/dvydra)


## Inspirations

* [Simply Versioned](http://github.com/github/simply_versioned)
* [Acts As Audited](http://github.com/collectiveidea/acts_as_audited)


## Intellectual Property

Copyright (c) 2011 Andy Stewart (boss@airbladesoftware.com).
Released under the MIT licence.
