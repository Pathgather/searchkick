require "bundler/setup"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "logger"

require 'active_support/core_ext/object/try'

ENV["RACK_ENV"] = "test"

Minitest::Test = Minitest::Unit::TestCase unless defined?(Minitest::Test)

File.delete("elasticsearch.log") if File.exists?("elasticsearch.log")
Searchkick.client.transport.logger = Logger.new("elasticsearch.log")

I18n.config.enforce_available_locales = true

ActiveJob::Base.logger = nil if defined?(ActiveJob)

if defined?(Mongoid)

  def mongoid2?
    Mongoid::VERSION.starts_with?("2.")
  end

  if mongoid2?
    # enable comparison of BSON::ObjectIds
    module BSON
      class ObjectId
        def <=>(other)
          self.data <=> other.data
        end
      end
    end
  end

  Mongoid.configure do |config|
    if mongoid2?
      config.master = Mongo::Connection.new.db("searchkick_test")
    else
      config.connect_to "searchkick_test"
    end
  end

  class Product
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name
    field :store_id, type: Integer
    field :in_stock, type: Boolean
    field :backordered, type: Boolean
    field :orders_count, type: Integer
    field :price, type: Integer
    field :color
    field :latitude, type: BigDecimal
    field :longitude, type: BigDecimal
    field :description
  end

  class Store
    include Mongoid::Document

    field :name
  end

  class Animal
    include Mongoid::Document

    field :name
  end

  class Dog < Animal
  end

  class Cat < Animal
  end
elsif defined? Sequel
  DB = Sequel.sqlite

  # DB.loggers << Logger.new(STDOUT)

  Sequel::Model.plugin :active_model
  Sequel::Model.plugin :hook_class_methods

  DB.create_table :products do
    primary_key :id
    string :name
    integer :store_id
    boolean :in_stock
    boolean :backordered
    integer :orders_count
    integer :price
    string :color
    decimal :latitude, precision: 10, scale: 7
    decimal :longitude, precision: 10, scale: 7
    timestamp :created_at
    timestamp :updated_at
  end

  DB.create_table :parts do
    primary_key :id
    string :name
    integer :product_id
    integer :total
  end

  DB.create_table :stores do
    primary_key :id
    string :name
  end

  DB.create_table :animals do
    primary_key :id
    string :name
    string :type
  end

  class Product < Sequel::Model
    unrestrict_primary_key
  end

  class Part < Sequel::Model
    unrestrict_primary_key
  end

  class Store < Sequel::Model
    unrestrict_primary_key
  end

  class Animal < Sequel::Model
    unrestrict_primary_key
  end

  class Dog < Animal
  end

  class Cat < Animal
  end
elsif defined?(NoBrainer)
  NoBrainer.configure do |config|
    config.app_name = :searchkick
    config.environment = :test
  end

  class Product
    include NoBrainer::Document
    include NoBrainer::Document::Timestamps

    field :name,         type: String
    field :store_id,     type: Integer
    field :in_stock,     type: Boolean
    field :backordered,  type: Boolean
    field :orders_count, type: Integer
    field :price,        type: Integer
    field :color,        type: String
    field :latitude
    field :longitude
    field :description,  type: String
  end

  class Store
    include NoBrainer::Document

    field :name, type: String
  end

  class Animal
    include NoBrainer::Document

    field :name, type: String
  end

  class Dog < Animal
  end

  class Cat < Animal
  end
else
  require "active_record"

  # for debugging
  # ActiveRecord::Base.logger = Logger.new(STDOUT)

  # rails does this in activerecord/lib/active_record/railtie.rb
  ActiveRecord::Base.default_timezone = :utc
  ActiveRecord::Base.time_zone_aware_attributes = true

  # migrations
  ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

  ActiveRecord::Base.raise_in_transactional_callbacks = true if ActiveRecord::Base.respond_to?(:raise_in_transactional_callbacks=)

  ActiveRecord::Migration.create_table :products do |t|
    t.string :name
    t.integer :store_id
    t.boolean :in_stock
    t.boolean :backordered
    t.integer :orders_count
    t.integer :price
    t.string :color
    t.decimal :latitude, precision: 10, scale: 7
    t.decimal :longitude, precision: 10, scale: 7
    t.text :description
    t.timestamps null: true
  end

  ActiveRecord::Migration.create_table :parts do |t|
    t.string :name
    t.integer :product_id
    t.integer :total
  end

  ActiveRecord::Migration.create_table :stores do |t|
    t.string :name
  end

  ActiveRecord::Migration.create_table :animals do |t|
    t.string :name
    t.string :type
  end

  class Product < ActiveRecord::Base
  end

  class Part < ActiveRecord::Base
  end

  class Store < ActiveRecord::Base
  end

  class Animal < ActiveRecord::Base
  end

  class Dog < Animal
  end

  class Cat < Animal
  end
end

class Product
  # belongs_to :store
  many_to_one :store

  searchkick \
    synonyms: [
      ["clorox", "bleach"],
      ["scallion", "greenonion"],
      ["saranwrap", "plasticwrap"],
      ["qtip", "cottonswab"],
      ["burger", "hamburger"],
      ["bandaid", "bandag"]
    ],
    autocomplete: [:name],
    suggest: [:name, :color],
    conversions: "conversions",
    personalize: "user_ids",
    locations: ["location", "multiple_locations"],
    text_start: [:name],
    text_middle: [:name],
    text_end: [:name],
    word_start: [:name],
    word_middle: [:name],
    word_end: [:name],
    mappings: {
      product: {},
      part: {
        _routing: {
          required: true,
          path: "product_id"
        },
        _parent: {
          type: "product"
        },
      }
    },
    merge_mappings: true,
    child: "Part",
    highlight: [:name],
    unsearchable: [:description]

  attr_accessor :conversions, :user_ids, :aisle

  def search_data
    serializable_hash.except("id").merge(
      conversions: conversions,
      user_ids: user_ids,
      location: [latitude, longitude],
      multiple_locations: [[latitude, longitude], [0, 0]],
      aisle: aisle
    )
  end

  def should_index?
    name != "DO NOT INDEX"
  end
end

class Part
  searchkick parent: "Product"

  def elasticsearch_parent_id
    product_id
  end
end

class Store
  searchkick mappings: {
    store: {
      properties: {
        name: {type: "string", analyzer: "keyword"}
      }
    }
  }
end

class Animal
  searchkick \
    autocomplete: [:name],
    suggest: [:name],
    index_name: -> { "#{self.name.tableize}-#{Date.today.year}" }
    # wordnet: true
end

Product.searchkick_index.delete if Product.searchkick_index.exists?
Product.reindex
Product.reindex # run twice for both index paths

Store.reindex
Animal.reindex

class Minitest::Test

  def setup
    Product.each &:destroy
    Part.each &:destroy
    Store.each &:destroy
    Animal.each &:destroy
  end

  protected

  def store(documents, klass = Product)
    documents.shuffle.each do |document|
      klass.create(document)
    end
    klass.searchkick_index.refresh
  end

  def store_names(names, klass = Product)
    store names.map{|name| {name: name} }, klass
  end

  # no order
  def assert_search(term, expected, options = {}, klass = Product)
    assert_equal expected.sort, klass.search(term, options).map(&:name).sort
  end

  def assert_order(term, expected, options = {}, klass = Product)
    assert_equal expected, klass.search(term, options).map(&:name)
  end

  def assert_first(term, expected, options = {}, klass = Product)
    assert_equal expected, klass.search(term, options).map(&:name).first
  end

end
