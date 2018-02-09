require 'resque'
require 'resque-scheduler'

category "Resque"

sample_interval 10

Resque.redis = Redis.new

describe_samples do
  cluster = ENV['ECS_CLUSTER']
  queue_sizes = ::Resque.queue_sizes
  queue_name_prefix = "#{cluster.rpartition('-').last}_"
  queue_sizes.select! {|k, _| k.start_with?(queue_name_prefix) }
  queue_names = queue_sizes.keys
  pending = queue_sizes.values.reduce(&:+) || 0
  workers = ::Resque.workers.select {|w| queue_names.any? {|name| w.queues.include?(name) } }

  delayed = ::Resque.find_delayed_selection do |args|
    args.any? {|arg| Hash === arg && queue_names.include?(arg['queue_name']) }
  end.count

  opts = {aggregate: {}, dimensions: {ClusterName: cluster}}

  sample(**opts, name: "Working", unit: "Count", value: workers.count(&:working?))
  sample(**opts, name: "Workers", unit: "Count", value: workers.count)
  sample(**opts, name: "Pending", unit: "Count", value: pending, storage_resolution: 1)
  if workers.count > 0
    sample(**opts, name: "Pending per Worker", unit: "Count", value: pending.to_f / workers.count,
        storage_resolution: 1)
  end

  sample(**opts, name: "Delayed", unit: "Count", value: delayed)
end
