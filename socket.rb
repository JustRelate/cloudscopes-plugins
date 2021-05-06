category "Docker Nginx"

sample_interval 10

describe_samples do
  aggregation_dimensions = {
    group: ENV['CS_AGGREGATION_GROUP'],
  }.compact

  if ENV["PUMA_STATS_FILE_PATH"].to_s != ""
    stats_file = File.expand_path(ENV["PUMA_STATS_FILE_PATH"], "/var/www/railsapp")
    begin
      stats = File.read(stats_file)

      data = stats.scan(/"rack_active"\s*:\s*(\d+)/).first
      rack_active = data.first.to_i if data

      data = stats.scan(/"rack_queued"\s*:\s*(\d+)/).first
      rack_queued = data.first.to_i if data
    rescue # rubocop:disable Style/RescueStandardError
      # maybe report - later
    end
  end

  # Fallback solution - if the stats file is not configured or not readable or
  # some other problem happened parsing it.
  if rack_queued.nil?
    rack_active = rack_queued = 0

    File.readlines("/proc/net/unix").each do |line|
      next unless line.end_with?("/puma.sock")

      inode = line.split(" ")[6]
      next unless inode

      if inode == "0"
        rack_queued += 1
      else
        rack_active += 1
      end
    end
  end

  [
    ["Active Rack Connections", rack_active],
    ["Queued Rack Connections", rack_queued]
  ].each do |(name, value)|
    sample(
      name: name,
      value: value,
      unit: "Count",
      storage_resolution: 1,
      aggregate: aggregation_dimensions,
      dimensions: {
        ClusterName: ec2.ecs_cluster,
      }
    )
  end
end
