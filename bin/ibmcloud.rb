
module IBMCloud
  class CLI
    def initialize( region )
      @region = region
    end

    def execute( cmd, **args )
      if args.include? 'json'
        plugin = cmd.split[ 0 ]
        if %w[ is ].include? plugin
          json_option = '--json'
        elsif %w[ tg ].include? plugin
          json_option = '--output json'
        end
      end

      cmd += " #{json_option}"

      popen2e ...

    end

    def login
      puts "Logging in to IBM Cloud..."
      self.execute "login -r #{@region}"
    end




  end # class
end
