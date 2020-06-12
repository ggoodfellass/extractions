defmodule Commons do
  require Logger

  def get_head_tail([]), do: []
  def get_head_tail(nil), do: []
  def get_head_tail([head|tail]) do
    [[head]|get_head_tail(tail)]
  end

  def intervaling(0), do: 1
  def intervaling(n), do: n

  def save_current_jpeg_time(url, path, :v2) do
    File.write!("#{path}CURRENT", url <> "\n", [:append])
  end

  def seaweedfs_save(camera_exid, timestamp, image) do
    server = Extraction.point_to_seaweed(String.to_integer(timestamp))
    hackney = [pool: :seaweedfs_upload_pool]
    directory_path = construct_directory_path(camera_exid, timestamp, "recordings", "")
    file_name = construct_file_name(timestamp)
    file_path = directory_path <> file_name
    case HTTPoison.post("#{server.url}#{file_path}", {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[seaweedfs_save] [#{file_path}] [#{camera_exid}] [#{inspect error}]"
    end
  end

  defp construct_directory_path(camera_exid, timestamp, app_dir, root_dir) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("#{root_dir}/#{camera_exid}/snapshots/#{app_dir}/%Y/%m/%d/%H/")
  end

  defp construct_file_name(timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%M_%S_%f")
    |> format_file_name
  end

  defp format_file_name(<<file_name::bytes-size(6)>>) do
    "#{file_name}000" <> ".jpg"
  end

  defp format_file_name(<<file_name::bytes-size(7)>>) do
    "#{file_name}00" <> ".jpg"
  end

  defp format_file_name(<<file_name::bytes-size(9), _rest :: binary>>) do
    "#{file_name}" <> ".jpg"
  end
end
