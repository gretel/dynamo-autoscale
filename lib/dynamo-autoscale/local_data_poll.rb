module DynamoAutoscale
  class LocalDataPoll < Poller
    include DynamoAutoscale::Logger

    def initialize *args
      super(*args)
      @cache = Hash.new { |h, k| h[k] = {} }
    end

    def poll tables, &block
      path = File.join(DynamoAutoscale.data_dir, '*.json')
      directory = Dir[path]
      tables ||= ["*"]

      tables.each do |table_name|
        # skip if cached
        unless @cache[table_name].empty?
          @cache[table_name].each do |day, table_day_data|
            block.call(table_name, table_day_data)
          end
        else
          file = "#{table_name}.json"
          directory.each do |table_path|
            logger.info "[local_data_poll] Reading data for '#{table_name}' from '#{table_path}'."
            data = JSON.parse(File.read(table_path)).symbolize_keys
            if data[:consumed_writes].nil? or data[:consumed_reads].nil?
              logger.warn "[local_data_poll] Lacking 'consumed_*' data for table '#{table_name}', skipping..."
              next
            end
            # All this monstrosity below is doing is parsing the time keys in
            # the nested hash from strings into Time objects. Hash mapping
            # semantics are weird, hence why this looks ridiculous.
            data = Hash[data.map do |key, ts|
              [
                key,
                Hash[ts.map do |t, d|
                  [Time.parse(t), d]
                end],
              ]
            end]
            @cache[table_name] = data
            block.call(table_name, data)
          end
        end
      end
    end
  end
end
