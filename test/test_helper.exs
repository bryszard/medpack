# Configure ExVCR
ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes")

# Ensure cassette directory exists
File.mkdir_p!("test/fixtures/vcr_cassettes")

# Filter out sensitive data from cassettes
ExVCR.Config.filter_sensitive_data("sk-[^\"\s]+", "sk-OPENAI_API_KEY_PLACEHOLDER")
ExVCR.Config.filter_sensitive_data("Bearer sk-[^\"\s]+", "Bearer sk-OPENAI_API_KEY_PLACEHOLDER")

# Configure test environment
Application.put_env(:medpack, :file_storage_backend, :local)
Application.put_env(:medpack, :upload_path, Path.expand("../tmp/test_uploads", __DIR__))
Application.put_env(:medpack, :temp_upload_path, Path.expand("../tmp/test_temp_uploads", __DIR__))

# Ensure test upload directories exist
File.mkdir_p!(Application.get_env(:medpack, :upload_path))
File.mkdir_p!(Application.get_env(:medpack, :temp_upload_path))

# Start ExUnit
ExUnit.start()

# Configure Ecto sandbox
Ecto.Adapters.SQL.Sandbox.mode(Medpack.Repo, :manual)
