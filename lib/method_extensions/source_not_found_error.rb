module MethodExtensions
  class SourceNotFoundError < ArgumentError
    def initialize(lines)
      message = "failed to find method definition around the lines: \n"
      message << lines.join("\n")
      super message
    end
  end
end
