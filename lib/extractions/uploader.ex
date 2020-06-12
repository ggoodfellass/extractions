defmodule Uploader do
  @root_dir "storage"

  require Logger
  import Commons

  def start(from, to) do

    uploading = fn (tuple) ->
      upload(tuple)
    end

    dir = @root_dir <> "/" <> from <> "/"
    stream_it(dir, to)
    # |> Enum.each(&upload(&1))
    |> Task.async_stream(&(uploading.(&1)), max_concurrency: System.schedulers_online() * 2, timeout: :infinity)
    |> Stream.run
  end

  defp upload(%{
    timestamp: timestamp,
    image: image,
    camera_exid: camera_exid})
  do
    seaweedfs_save(camera_exid, timestamp, image)
  end
  defp upload([]), do: :noop

  defp stream_it(dir, to) do
    File.ls!(dir)
    |> Enum.map(&compose(&1, dir, to))
  end

  defp compose("CURRENT", _dir, _to), do: []
  defp compose(file, dir, to) do
    timestamp =
      String.split(file, ".")
      |> List.first
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.DateTime.to_erl
      |> Calendar.DateTime.from_erl!("Europe/Dublin")
      |> Calendar.DateTime.shift_zone!("Etc/UTC")
      |> Calendar.DateTime.Format.unix
    image = File.read!(dir <> file)
    %{
      timestamp: timestamp,
      image: image,
      camera_exid: to
    }
  end
end