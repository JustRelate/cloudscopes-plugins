category "Docker Container"

describe_samples do
  if container_filter = ENV['CS_DOCKER_CONTAINER_NAME_FILTER']
    container_ids = docker.ps(name_filter: container_filter)
    instance_id = ec2.instance_id
    container_ids.each do |c_id|
      i_total, i_used, i_avail =
          *docker.exec(c_id, "df", "-i", "/").split("\n").last.split.map(&:to_i)
      total, used, avail =
          *docker.exec(c_id, "df", "-B", "1", "/").split("\n").last.split.map(&:to_i)
      data = [
        ["FS Inode Usage", "Percent", i_used.to_f / i_total * 100],
        ["FS Space Usage", "Percent", used.to_f / total * 100],
      ]
      dimensions = {InstanceId: instance_id, ContainerId: c_id}
      data.each do |name, unit, value|
        sample(name: name, unit: unit, value: value, dimensions: {})
        sample(name: name, unit: unit, value: value, dimensions: dimensions)
      end
    end
  end
end
