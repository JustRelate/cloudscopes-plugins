require 'resque'
require 'resque-scheduler'

category "Resque"

sample_interval 10

Resque.redis = Redis.new

describe_samples do
  queue_sizes = ::Resque.queue_sizes
  queue_name_prefix = "#{ec2.ecs_cluster.rpartition('-').last}_"
  pending_per_queue = queue_sizes
    .select {|k, _| k.start_with?(queue_name_prefix) }
    .transform_keys {|k| k[queue_name_prefix.size..-1] }
  pending = pending_per_queue.values.reduce(&:+) || 0
  workers = ::Resque.workers.select {|w| w.queues.any? {|q| q.start_with?(queue_name_prefix) } }

  ::Resque::Worker.all_workers_with_expired_heartbeats.each do |worker|
    next unless workers.include?(worker)

    # prune code copied from ::Resque::Worker#prune_dead_workers which does too many other things
    job_class = worker.job(false)&.[]('payload')&.[]('class')
    worker.unregister_worker(::Resque::PruneDeadWorkerDirtyExit.new(worker.to_s, job_class))
    workers -= [worker]
  end
  working_per_queues = Hash.new(0)
  working = 0
  workers.select(&:working?).each do |w|
    key = w.queues.map {|n| n[queue_name_prefix.size..-1] }.sort.join(", ")
    working_per_queues[key] += 1
    working += 1
  end

  delayed_per_queue = Hash.new(0)
  delayed = 0
  ::Resque.find_delayed_selection do |args|
    args.any? do |arg|
      if arg.is_a?(Hash)
        queue = arg['queue_name']
        if queue.start_with?(queue_name_prefix)
          delayed_per_queue[queue[queue_name_prefix.size..-1]] += 1
          delayed += 1
          true
        end
      end
    end
  end

  opts = {aggregate: {}, dimensions: {ClusterName: ec2.ecs_cluster}}

  working_per_queues.each do |k, v|
    sample(**opts, name: "Working #{k}", unit: "Count", value: v, storage_resolution: 1)
  end
  sample(**opts, name: "Working low-res", unit: "Count", value: working)

  pending_per_queue.each do |k, v|
    sample(**opts, name: "Pending #{k}", unit: "Count", value: v, storage_resolution: 1)
  end
  sample(**opts, name: "Pending low-res", unit: "Count", value: pending)

  delayed_per_queue.each do |k, v|
    sample(**opts, name: "Delayed #{k}", unit: "Count", value: v)
  end
  sample(**opts, name: "Delayed", unit: "Count", value: delayed)
end
