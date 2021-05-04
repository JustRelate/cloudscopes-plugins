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
  parsed = stats.scan(/"pool_capacity":\s*(\d+),\s*"max_threads":\s*(\d+)[^\d]/)

  # indicate unexpected stats by not reporting the sample
  next if parsed.empty?

  free_capacity = parsed.map(&:first).sum
  max_capacity = parsed.map(&:last).sum

  aggregation_dimensions = {}
  if (aggregation_group = ENV['CS_AGGREGATION_GROUP'])
    aggregation_dimensions[:group] = aggregation_group
  end
  opts = {
    aggregate: aggregation_dimensions,
    dimensions: {ClusterName: ec2.ecs_cluster},
  }
  sample(**opts, name: "Puma Free Capacity", unit: "Count", value: free_capacity, storage_resolution: 1)
  sample(**opts, name: "Puma Max Capacity", unit: "Count", value: max_capacity, storage_resolution: 1)
  sample(**opts, name: "Puma Used Capacity", unit: "Count", value: max_capacity - free_capacity, storage_resolution: 1)
  if max_capacity.positive?
    relative_capacity = free_capacity / max_capacity.to_f
    sample(**opts, name: "Puma Free Relative Capacity", unit: "Count", value: relative_capacity, storage_resolution: 1)
  end
end
