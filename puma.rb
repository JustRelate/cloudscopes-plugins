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

  free_capacity = parsed.map(&:first).map(&:to_i).sum
  max_capacity = parsed.map(&:last).map(&:to_i).sum

  names_and_values = []
  names_and_values << ["Puma Free Capacity", free_capacity, "Count"]
  names_and_values << ["Puma Max Capacity", max_capacity, "Count"]
  names_and_values << ["Puma Used Capacity", max_capacity - free_capacity, "Count"]
  if max_capacity.positive?
    relative_capacity = 100.0 * free_capacity / max_capacity.to_f
    names_and_values << ["Puma Free Relative Capacity", relative_capacity, "Percent"]
  end

  aggregation_dimensions = {}
  if (aggregation_group = ENV['CS_AGGREGATION_GROUP'])
    aggregation_dimensions[:group] = aggregation_group
  end

  names_and_values.each do |(name, value, unit)|
    sample(
      aggregate: aggregation_dimensions,
      dimensions: {ClusterName: ec2.ecs_cluster},
      name: name,
      storage_resolution: 60,
      unit: unit,
      value: value
    )
  end
end
