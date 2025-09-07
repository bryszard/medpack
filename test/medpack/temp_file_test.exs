defmodule Medpack.TempFileTest do
  use ExUnit.Case
  alias Medpack.TempFile

  describe "with_temp_file/2" do
    test "creates and cleans up temp file" do
      temp_path_ref = make_ref()

      result = TempFile.with_temp_file(".txt", fn temp_file ->
        # Store the path in the process dictionary so we can access it later
        Process.put(temp_path_ref, temp_file.path)

        assert String.ends_with?(temp_file.path, ".txt")
        assert String.contains?(temp_file.path, System.tmp_dir!())

        # Write some content to verify the file can be used
        File.write!(temp_file.path, "test content")
        assert File.exists?(temp_file.path)

        "success"
      end)

      temp_path = Process.get(temp_path_ref)
      assert result == "success"
      # File should be cleaned up after callback
      assert not File.exists?(temp_path)
    end

    test "cleans up temp file even when error is raised" do
      temp_path_ref = make_ref()

      assert_raise RuntimeError, "test error", fn ->
        TempFile.with_temp_file(".txt", fn temp_file ->
          # Store the path in the process dictionary so we can access it later
          Process.put(temp_path_ref, temp_file.path)

          File.write!(temp_file.path, "test content")
          assert File.exists?(temp_file.path)

          raise "test error"
        end)
      end

      temp_path = Process.get(temp_path_ref)
      # File should still be cleaned up after error
      assert not File.exists?(temp_path)
    end

    test "handles nil extension" do
      TempFile.with_temp_file(nil, fn temp_file ->
        # Should not end with any extension
        assert not String.contains?(Path.basename(temp_file.path), ".")
        assert String.contains?(temp_file.path, System.tmp_dir!())
      end)
    end

    test "handles empty extension" do
      TempFile.with_temp_file("", fn temp_file ->
        # Should not end with any extension
        assert not String.contains?(Path.basename(temp_file.path), ".")
        assert String.contains?(temp_file.path, System.tmp_dir!())
      end)
    end
  end
end
