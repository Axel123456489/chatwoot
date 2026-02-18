# Ensure RubyLLM::Chat responds to hooks expected in specs
if defined?(RubyLLM::Chat)
  RubyLLM::Chat.class_eval do
    def on_tool_result(*)
      self
    end
  end
end
