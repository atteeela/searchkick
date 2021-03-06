module Searchkick
  module Reindex

    # https://gist.github.com/jarosan/3124884
    def reindex
      alias_name = tire.index.name
      new_index = alias_name + "_" + Time.now.strftime("%Y%m%d%H%M%S")
      index = Tire::Index.new(new_index)

      index.create searchkick_index_options

      # use scope for import
      scope = respond_to?(:search_import) ? search_import : self
      scope.find_in_batches do |batch|
        index.import batch
      end

      if a = Tire::Alias.find(alias_name)
        old_indices = a.indices.dup
        old_indices.each do |index|
          a.indices.delete index
        end

        a.indices.add new_index
        response = a.save

        if response.success?
          old_indices.each do |index|
            i = Tire::Index.new(index)
            i.delete
          end
        end
      else
        tire.index.delete
        response = Tire::Alias.create(name: alias_name, indices: [new_index])
      end

      response.success? || (raise response.to_s)
    end

    private

    def searchkick_index_options
      options = @searchkick_options

      settings = {
        analysis: {
          analyzer: {
            searchkick_keyword: {
              type: "custom",
              tokenizer: "keyword",
              filter: ["lowercase", "snowball"]
            },
            default_index: {
              type: "custom",
              tokenizer: "standard",
              # synonym should come last, after stemming and shingle
              # shingle must come before snowball
              filter: ["standard", "lowercase", "asciifolding", "stop", "snowball", "searchkick_index_shingle"]
            },
            searchkick_search: {
              type: "custom",
              tokenizer: "standard",
              filter: ["standard", "lowercase", "asciifolding", "stop", "snowball", "searchkick_search_shingle"]
            },
            searchkick_search2: {
              type: "custom",
              tokenizer: "standard",
              filter: ["standard", "lowercase", "asciifolding", "stop", "snowball"]
            }
          },
          filter: {
            searchkick_index_shingle: {
              type: "shingle",
              token_separator: ""
            },
            # lucky find http://web.archiveorange.com/archive/v/AAfXfQ17f57FcRINsof7
            searchkick_search_shingle: {
              type: "shingle",
              token_separator: "",
              output_unigrams: false,
              output_unigrams_if_no_shingles: true
            }
          }
        }
      }.merge(options[:settings] || {})
      synonyms = options[:synonyms] || []
      if synonyms.any?
        settings[:analysis][:filter][:searchkick_synonym] = {
          type: "synonym",
          ignore_case: true,
          synonyms: synonyms.select{|s| s.size > 1 }.map{|s| "#{s[0..-2].join(",")} => #{s[-1]}" }
        }
        settings[:analysis][:analyzer][:default_index][:filter] << "searchkick_synonym"
        settings[:analysis][:analyzer][:searchkick_search][:filter].insert(-2, "searchkick_synonym")
        settings[:analysis][:analyzer][:searchkick_search][:filter] << "searchkick_synonym"
        settings[:analysis][:analyzer][:searchkick_search2][:filter] << "searchkick_synonym"
      end

      mapping = {}
      if options[:conversions]
        mapping[:conversions] = {
          type: "nested",
          properties: {
            query: {type: "string", analyzer: "searchkick_keyword"},
            count: {type: "integer"}
          }
        }
      end

      mappings = {
        document_type.to_sym => {
          properties: mapping
        }
      }

      {
        settings: settings,
        mappings: mappings
      }
    end

  end
end
