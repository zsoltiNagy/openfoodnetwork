# frozen_string_literal: true

module DataFoodConsortium
  module Connector
    class Importer
      TYPES = [
        DataFoodConsortium::Connector::CatalogItem,
        DataFoodConsortium::Connector::Enterprise,
        DataFoodConsortium::Connector::Offer,
        DataFoodConsortium::Connector::Person,
        DataFoodConsortium::Connector::QuantitativeValue,
        DataFoodConsortium::Connector::SuppliedProduct,
      ].freeze

      def self.type_map
        @type_map ||= TYPES.each_with_object({}) do |clazz, result|
          type_uri = clazz.new(nil).semanticType
          result[type_uri] = clazz
        end
      end

      def import(json_string)
        @subjects = {}

        graph = parse_rdf(json_string)
        apply_statements(graph)

        if @subjects.size > 1
          @subjects.values
        else
          @subjects.values.first
        end
      end

      private

      def parse_rdf(json_string)
        json_file = StringIO.new(json_string)
        RDF::Graph.new << JSON::LD::API.toRdf(json_file)
      end

      def build_subject(type_statement)
        id = type_statement.subject.value
        type = type_statement.object.value
        clazz = self.class.type_map[type]

        clazz.new(id)
      end

      def apply_statements(statements)
        statements.each do |statement|
          apply_statement(statement)
        end
      end

      def apply_statement(statement)
        subject = subject_of(statement)
        property_id = statement.predicate.value
        value = statement.object.object

        return unless subject.hasSemanticProperty?(property_id)

        property = subject.__send__(:findSemanticProperty, property_id)

        # Some properties have a one-to-one match to the method name.
        setter_name = "#{statement.predicate.fragment}="

        if property.value.is_a?(Enumerable)
          property.value << value
        elsif subject.respond_to?(setter_name)
          subject.public_send(setter_name, value)
        end
      end

      def subject_of(statement)
        @subjects[statement.subject] ||= build_subject(statement)
      end
    end
  end
end
