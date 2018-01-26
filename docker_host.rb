category "Docker Host"

describe_samples do
  processes = process.list.sort_by(&:mem_usage_rss)
  aggregation_dimensions = {}
  if aggregation_group = ENV['CS_AGGREGATION_GROUP']
    aggregation_dimensions[:group] = aggregation_group
  end
  opts = {
    aggregate: aggregation_dimensions,
    dimensions: {InstanceId: ec2.instance_id},
  }
  sample(**opts,
      name: "Load Per CPU", unit: "Percent", value: 100 * system.loadavg5 / system.cpucount)
  sample(**opts, name: "Pending I/O", unit: "Count", value: system.iostat[8])
  sample(**opts,
      name: "Memory Utilization", unit: "Percent", value: 100 * memory.MemUsed / memory.MemTotal)
  sample(**opts, name: "Largest Process Size",
      unit: "Megabytes", value: processes.last.mem_usage_rss / 1024**2)
  {
    "Background" => "resque-",
    "Web" => "unicorn_rails ",
  }.each do |type, prefix|
    if process = processes.select {|p| p.cmdline.start_with?(prefix) }.last
      sample(**opts, name: "Largest #{type} Worker Size",
          unit: "Megabytes", value: process.mem_usage_rss / 1024**2)
    end
  end

  data = filesystem.df("/")
  inode_usage = (data.files - data.files_available) * 100.0 / data.files
  space_usage = (data.blocks - data.blocks_available) * 100.0 / data.blocks
  sample(**opts, name: "Boot-FS Inode Usage", unit: "Percent", value: inode_usage)
  sample(**opts, name: "Boot-FS Space Usage", unit: "Percent", value: space_usage)

  data = JSON.parse(`lvdisplay -C --reportformat json docker`)['report'].first['lv'].first
  sample(**opts,
      name: "Docker Storage Usage (data)", unit: "Percent", value: data['data_percent'].to_f)
  sample(**opts, name: "Docker Storage Usage (metadata)",
      unit: "Percent", value: data['metadata_percent'].to_f)
end
