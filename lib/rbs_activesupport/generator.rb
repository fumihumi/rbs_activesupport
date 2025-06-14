# frozen_string_literal: true

module RbsActivesupport
  class Generator
    # @rbs pathname: Pathname
    # @rbs rbs_builder: RBS::DefinitionBuilder
    def self.generate(pathname, rbs_builder) #: String?
      new(pathname, rbs_builder).generate
    rescue StandardError
      warn "Failed to generate RBS for #{pathname}"
    end

    include AST

    attr_reader :pathname #: Pathname
    attr_reader :declaration_builder #: DeclarationBuilder

    # @rbs pathname: Pathname
    # @rbs rbs_builder: RBS::DefinitionBuilder
    def initialize(pathname, rbs_builder) #: void
      @pathname = pathname

      method_searcher = MethodSearcher.new(rbs_builder)
      resolver = RBS::Resolver::TypeNameResolver.new(rbs_builder.env)
      @declaration_builder = DeclarationBuilder.new(resolver, method_searcher)
    end

    def generate #: String?
      declarations = parse_source_code
      return if declarations.empty?

      definition = declarations.map do |namespace, method_calls|
        public_decls, private_decls = declaration_builder.build(namespace, method_calls)
        next if public_decls.empty? && private_decls.empty?

        <<~RBS
          # resolve-type-names: false

          #{header(namespace)}
          #{public_decls.join("\n")}

          #{"private" if private_decls.any?}

          #{private_decls.join("\n")}

          #{footer(namespace)}
        RBS
      end.compact.join("\n")

      return if definition.empty?

      format(definition)
    end

    private

    # @rbs rbs: String
    def format(rbs) #: String
      parsed = RBS::Parser.parse_signature(rbs)
      StringIO.new.tap do |out|
        RBS::Writer.new(out:).write(parsed[1] + parsed[2])
      end.string
    end

    def parse_source_code #: Hash[RBS::Namespace, Array[Parser::MethodCall]]
      parser = Parser.new
      parser.parse(pathname.read)
      parser.method_calls
    end

    # @rbs namespace: RBS::Namespace
    def header(namespace) #: String
      namespace_to_names(namespace).map do |name|
        mod_object = Object.const_get(name.to_s)
        case mod_object
        when Class
          superclass = mod_object.superclass
          superclass_name = superclass&.name || "::Object"

          "class #{name} < ::#{superclass_name}"
        when Module
          "module #{name}"
        else
          raise "unreachable"
        end
      end.join("\n")
    end

    # @rbs namespace: RBS::Namespace
    def footer(namespace) #: String
      "end\n" * namespace.path.size
    end

    # @rbs namespace: RBS::Namespace
    def namespace_to_names(namespace) #: Array[RBS::TypeName]
      names = [] #: Array[RBS::TypeName]
      until namespace.empty?
        names << namespace.to_type_name
        namespace = namespace.parent
      end
      names.reverse
    end
  end
end
