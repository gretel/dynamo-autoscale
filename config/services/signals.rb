Signal.trap('USR1') do
  DynamoAutoscale.logger.info "[signal] Caught USR1. Dumping CSV for all tables in #{Dir.pwd}"

  DynamoAutoscale.tables.each do |name, table|
    table.to_csv! path: File.join(Dir.pwd, "#{table.name}.csv")
  end
end

Signal.trap('USR2') do
  DynamoAutoscale.logger.info "[signal] Caught USR2. Dumping graphs for all tables in #{Dir.pwd}"

  DynamoAutoscale.tables.each do |name, table|
    # TODO: abstraction
    table.graph! output_file: File.join(Dir.pwd, "#{table.name}_graph.png"), r_script: 'dynamodb_graph.r'
    table.graph! output_file: File.join(Dir.pwd, "#{table.name}_scatter.png"), r_script: 'dynamodb_scatterplot.r'
  end
end

Kernel.trap('EXIT') do
  DynamoAutoscale.logger.info "[signal] Caught EXIT. Shutting down..."
end
