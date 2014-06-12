module Searchkick
  class Index
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def create(options = {})
      client.indices.create index: name, body: options
    end

    def delete
      client.indices.delete index: name
    end

    def exists?
      client.indices.exists index: name
    end

    def refresh
      client.indices.refresh index: name
    end

    def store(record)
      client.index identity(record).merge(body: search_data(record))
    end

    def remove(record)
      client.delete identity(record)
    end

    def import(records)
      records.group_by{|r| document_type(r) }.each do |type, batch|
        client.bulk(
          index: name,
          type: type,
          body: batch.map { |r|
            doc = {_id: search_id(r), data: search_data(r)}
            doc[:_parent] = r.elasticsearch_parent_id.to_s if r.respond_to?(:elasticsearch_parent_id)
            { index: doc }
          }
        )
      end
    end

    def retrieve(record)
      client.get(identity(record))["_source"]
    end

    def klass_document_type(klass)
      if klass.respond_to?(:document_type)
        klass.document_type
      else
        klass.model_name.to_s.underscore
      end
    end

    protected

    def client
      Searchkick.client
    end

    def identity(record)
      id = {
        index: name,
        type: document_type(record),
        id: search_id(record)
      }

      id[:parent] = record.elasticsearch_parent_id.to_s if record.respond_to?(:elasticsearch_parent_id)
      id
    end

    def document_type(record)
      klass_document_type(record.class)
    end

    def search_id(record)
      record.id.is_a?(Numeric) ? record.id : record.id.to_s
    end

    def search_data(record)
      source = record.search_data
      options = record.class.searchkick_options

      # stringify fields
      # remove _id since search_id is used instead
      source = source.inject({}){|memo,(k,v)| memo[k.to_s] = v; memo}.except("_id")

      # conversions
      conversions_field = options[:conversions]
      if conversions_field and source[conversions_field]
        source[conversions_field] = source[conversions_field].map{|k, v| {query: k, count: v} }
      end

      # hack to prevent generator field doesn't exist error
      (options[:suggest] || []).map(&:to_s).each do |field|
        source[field] = nil if !source[field]
      end

      # locations
      (options[:locations] || []).map(&:to_s).each do |field|
        if source[field]
          if source[field].first.is_a?(Array) # array of arrays
            source[field] = source[field].map{|a| a.map(&:to_f).reverse }
          else
            source[field] = source[field].map(&:to_f).reverse
          end
        end
      end

      cast_big_decimal(source)

      source.respond_to?(:as_json) ? source.as_json : source
    end

    # change all BigDecimal values to floats due to
    # https://github.com/rails/rails/issues/6033
    # possible loss of precision :/
    def cast_big_decimal(obj)
      case obj
      when BigDecimal
        obj.to_f
      when Hash
        obj.each do |k, v|
          obj[k] = cast_big_decimal(v)
        end
      when Enumerable
        obj.map do |v|
          cast_big_decimal(v)
        end
      else
        obj
      end
    end

  end
end
