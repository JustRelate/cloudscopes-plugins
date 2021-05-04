category "Puma"

sample_interval 10

describe_samples do
  stats_file = ENV["PUMA_STATS_FILE_PATH"].to_s
  next if stats_file == ""

  next if Time.now - File.mtime(stats_file) > 5

  stats = File.read(stats_file)
  unless stats.count("{") == stats.count("}")
    stats = File.read(stats_file)

    stats.count("{") == stats.count("}") or raise "Malformed puma stats json: #{stats}"
  end

  # poor man's json parser
  queue_sizes = stats.scan(/"backlog"\s*:\s*(\d+)[^\d]/).map(&:first).map(&:to_i)

  average_size = queue_sizes.sum / queue_sizes.size
  # indicate unexpected stats by not reporting the sample
  next if queue_sizes.empty?

  aggregation_dimensions = {}
  if (aggregation_group = ENV['CS_AGGREGATION_GROUP'])
    aggregation_dimensions[:group] = aggregation_group
  end
  opts = {
    aggregate: aggregation_dimensions,
    dimensions: {ClusterName: ec2.ecs_cluster},
  }
  sample(**opts, name: "Puma Queue Size", unit: "Count", value: average_size, storage_resolution: 1)
end
