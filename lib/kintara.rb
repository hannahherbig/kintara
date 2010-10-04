#
# kintara: malkier xmpp server
# lib/kintara.rb: startup routines, etc
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger optparse yaml).each { |m| require m }

# Import required application modules
%w(timer server).each { |m| require 'kintara/' + m }

# XXX - Since IDN doesn't work in 1.9 yet, we're going to just make sure the
# qualifying strings are set to be encoded as UTF-8.
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'

# Check for Sequel
begin
    require 'sequel'
rescue LoadError
    puts 'kintara: unable to load Sequel'
    puts 'kintara: this library is required for database storage'
    puts 'kintara: gem install --remote sequel'
    abort
end

# XXX - for quick reference
#
# { :domains => "malkier.net, optera.org",
#   :listen  => { :c2s => "*:5222",
#                 :s2s => "*:5269",
#                 :certificate => "etc/cert.pem" },
#   :authorize => { :matches => "(.*)" },
#                   :deny    => nil,
#   :operators => { :rakaur  => "announce" }

# The main application class
class Kintara
    # Project name
    ME = 'kintara'

    # Version number
    V_MAJOR  = 0
    V_MINOR  = 1
    V_PATCH  = 0

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_PATCH}"

    # Configuration data
    @@config = nil

    # Database connection
    @@db = nil

    # Application-wide Logger
    @@logger = nil

    # A list of our servers
    @@servers = []

    # The OpenSSL context used for STARTTLS
    @@ssl_context = nil

    # Application-wide time
    @@time = Time.now.to_f

    ##
    # Create a new +Kintara+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
        puts "#{ME}: version #{VERSION} [#{RUBY_PLATFORM}]"

        # Check to see if we're running on a decent version of ruby
        if RUBY_VERSION < '1.8.6'
            puts "#{ME}: requires at least ruby 1.8.6"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        elsif RUBY_VERSION < '1.9.1'
            puts "#{ME}: supports ruby 1.9 (much faster)"
            puts "#{ME}: you have #{RUBY_VERSION}"
        end

        # Check to see if we're running as root
        if Process.euid == 0
            puts "#{ME}: refuses to run as root"
            abort
        end

        # Some defaults for state
        logging  = true
        debug    = false
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd

        # Do command-line options
        opts = OptionParser.new

        dd = 'Enable debug logging.'
        hd = 'Display usage information.'
        nd = 'Do not fork into the background.'
        qd = 'Disable regular logging.'
        vd = 'Display version information.'

        opts.on('-d', '--debug',   dd) { debug    = true  }
        opts.on('-h', '--help',    hd) { puts opts; abort }
        opts.on('-n', '--no-fork', nd) { willfork = false }
        opts.on('-q', '--quiet',   qd) { logging  = false }
        opts.on('-v', '--version', vd) { abort            }

        begin
            opts.parse(*ARGV)
        rescue OptionParser::ParseError => err
            puts err, opts
            abort
        end

        # Interpreter warnings
        $-w = true if debug

        # Signal handlers
        trap(:INT)   { app_exit }
        trap(:TERM)  { app_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        # Load configuration file
        begin
            @@config = YAML.load_file('etc/config.yml')
        rescue Exception => e
            puts '----------------------------'
            puts "#{ME}: configure error: #{e}"
            puts '----------------------------'
            abort
        else
            keys_to_sym!(@@config)
        end

        # Set up the SSL stuff
        certfile = @@config[:listen][:certificate]
        keyfile  = @@config[:listen][:private_key]

        begin
            cert = OpenSSL::X509::Certificate.new(File.read(certfile))
            pkey = OpenSSL::PKey::RSA.new(File.read(keyfile))
        rescue Exception => e
            puts "#{ME}: configuration error: #{e}"
            abort
        else
            ctx      = OpenSSL::SSL::SSLContext.new
            ctx.cert = cert
            ctx.key  = pkey

            ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE

            @@ssl_context = ctx
        end

        if debug
            puts "#{ME}: warning: debug mode enabled"
            puts "#{ME}: warning: all streams will be logged in the clear!"
        end

        # Load database
        no_db = true if not File.exists?('etc/kintara.db')

        begin
            @@db = Sequel.sqlite('etc/kintara.db')
        rescue Exception => e
            puts "#{ME}: database error: #{e}"
            abort
        else
            # Sequel makes us open the db before we load our models...
            require 'kintara/database'
        end

        if no_db
            puts "#{ME}: creating new database..."
            DB.initialize
        end

        # Check to see if we're already running
        if File.exists?('var/kintara.pid')
            curpid = nil
            File.open('var/kintara.pid', 'r') { |f| curpid = f.read.chomp.to_i }

            begin
                Process.kill(0, curpid)
            rescue Errno::ESRCH, Errno::EPERM
                File.delete('var/kintara.pid')
            else
                puts "#{ME}: daemon is already running"
                abort
            end
        end

        # Fork into the background
        if willfork
            begin
                pid = fork
            rescue Exception => e
                puts "#{ME}: cannot fork into the background"
                abort
            end

            # This is the child process
            unless pid
                Dir.chdir(wd)
                File.umask(0)
            else # This is the parent process
                puts "#{ME}: pid #{pid}"
                puts "#{ME}: running in background mode from #{Dir.getwd}"
                abort
            end

            $stdin.close
            $stdout.close
            $stderr.close

            # Set up logging
            if logging or debug
                @@logger = Logger.new('var/kintara.log', 'weekly')
            end
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"

            # Set up logging
            @@logger = Logger.new($stdout) if logging or debug
        end

        # Log our SQL statements if debugging
        @@db.loggers << @@logger if debug

        #u = DB::User.new
        #u.node = 'rakaur'
        #u.domain = 'malkier.net'
        #u.password = Digest::MD5.hexdigest('partypants')
        #u.save

        # Write the PID file
        Dir.mkdir('var') unless Dir.exists?('var')
        File.open('var/kintara.pid', 'w') { |f| f.puts(Process.pid) }

        # XXX - timers

        # Start the listeners
        @@config[:listen].each do |type, value|
            next unless [:c2s, :s2s].include?(type)

            bind_to, port = value.split(':')

            @@servers << XMPP::Server.new do |s|
                s.bind_to = bind_to
                s.port    = port
                s.type    = type

                s.logger  = @@logger if logging
                s.debug   = debug
            end
        end

        Thread.abort_on_exception = true if debug

        @@servers.each { |s| s.thread = Thread.new { s.io_loop } }
        @@servers.each { |s| s.thread.join }

        @@logger.debug(caller[0].split('/')[-1]) { @@servers }

        # Exiting...
        app_exit

        # Return...
        self
    end

    ######
    public
    ######

    def Kintara.config
        @@config
    end

    def Kintara.db
        @@db
    end

    def Kintara.ssl_context
        @@ssl_context
    end

    def Kintara.time
        @@time
    end

    def Kintara.time=(value)
        @@time = value
    end

    def Kintara.servers
        @@servers
    end

    def Kintara.add_server(server)
        @@servers << server
    end

    #######
    private
    #######

    def keys_to_sym!(hash)
        to_del, to_add, vals = [], [], []

        hash.each do |k, v|
            to_del << k
            to_add << k.to_sym
            vals   << v
        end

        to_del.each { |d| hash.delete(d) }
        to_add.each_with_index { |a, i| hash[a] = vals[i] }
        vals.each { |v| keys_to_sym!(v) if v.is_a?(Hash) }

        hash
    end

    def app_exit
        @@logger.close if @@logger
        File.delete('var/kintara.pid')
        exit
    end
end

