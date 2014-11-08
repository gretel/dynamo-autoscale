# Eye self-configuration section
def local_path(*args)
  File.expand_path(File.join(File.dirname(__FILE__), *args))
end

Eye.config do
  logger local_path('log', 'supervisor.log')
end

# Application
Eye.application 'dynamo-autoscale' do
  working_dir local_path(%w[ run ])

  trigger :flapping, times: 5, within: 1.minute, retry_in: 15.minutes
  # check :cpu, every: 10.seconds, below: 95, times: 3

  process :daemon do
    pid_file local_path('run', 'dynamo-autoscale.pid')
    stdall local_path('log', 'dynamo-autoscale.log')

    start_command "#{local_path('bin', 'dynamic-autoscale')} start --config #{local_path('config', 'dynamo-autoscale.yml')}"
    # start_command "#{local_path('bin', 'dynamic-autoscale')} --trace start --debug --config #{local_path('config', 'dynamo-autoscale.yml')}"

    stop_signals [:QUIT, 3.seconds, :KILL]

    daemonize true

    check :cpu, below: 25, times: [3, 5]
    check :memory, every: 30.seconds, below: 100.megabytes, times: 3
  end
end
