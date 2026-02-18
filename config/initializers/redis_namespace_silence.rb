# Silence redis-namespace deprecation warnings
# This will be resolved when redis-namespace 2.0 is released
if defined?(Redis::Namespace)
  Redis::Namespace.class_eval do
    def self.deprecate(message)
      # Silently ignore deprecation warnings
    end
  end
end
