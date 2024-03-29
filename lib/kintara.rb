#
# kintara: malkier xmpp server
# lib/kintara.rb: startup routines, etc
#
# Copyright (c) 2003-2011 Eric Will <rakaur@malkier.net>
#

# Import required Ruby modules
require 'logger'
require 'optparse'

# Import required application modules
require 'kintara/config'
require 'kintara/loggable'
require 'kintara/timer'
require 'kintara/server'

# Check for Sequel & SQLite
begin
    lib = nil
    %w(sequel sqlite3).each { |m| lib = m; require lib }
rescue LoadError => e
    puts "kintara: could not load #{lib}"
    puts 'kintara: this library is required for database storage'
    puts "kintara: gem install --remote #{lib}"
    abort
end

# The main application class
class Kintara
    ##
    # mixins
    include Loggable

    ##
    # constants

    # Project name
    ME = 'kintara'

    # Version number
    V_MAJOR  = 0
    V_MINOR  = 1
    V_PATCH  = 0

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_PATCH}"

    ##
    # class variables

    # Configuration data
    @@config = nil

    # Database connection
    @@db = nil

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

        # XXX 1.8 doesn't work atm because of IO::WaitReadable
        if RUBY_VERSION < '1.8.8'
            puts "#{ME}: support for 1.8 is broken due to IO::WaitReadable"
        end

        # Check to see if we're running on a decent version of ruby
        if RUBY_VERSION < '1.9' and RUBY_VERSION < '1.8.7'
            puts "#{ME}: requires at least ruby 1.8.7"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        elsif RUBY_VERSION > '1.9' and RUBY_VERSION < '1.9.2'
            puts "#{ME}: requires at least ruby 1.9.2"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        end

        # Check to see if we're running as root
        if Process.euid == 0
            puts "#{ME}: refuses to run as root"
            abort
        end

        # XXX - Since IDN doesn't work in 1.9 yet, we're going to just
        # make sure the qualifying strings are set to be encoded as UTF-8.
        if RUBY_VERSION >= '1.9.2'
            Encoding.default_internal = 'UTF-8'
            Encoding.default_external = 'UTF-8'
        end

        # Some defaults for state
        logging  = true
        debug    = false
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd
        @logger  = nil

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

        # Set up the SSL stuff
        @@config.vhosts.each do |name, vhost|
            next unless vhost.respond_to?(:ssl_certfile)
            next unless vhost.respond_to?(:ssl_keyfile)

            certfile = vhost.ssl_certfile
            keyfile  = vhost.ssl_keyfile

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
                ctx.options     = OpenSSL::SSL::OP_NO_TICKET
                ctx.options    |= OpenSSL::SSL::OP_NO_SSLv2
                ctx.options    |= OpenSSL::SSL::OP_ALL

                vhost.ssl_context = ctx
            end
        end

        if debug
            puts "#{ME}: warning: debug mode enabled"
            puts "#{ME}: warning: all streams will be logged in the clear!"
        end

        # Load database
        no_db = true if not File.exists?('etc/kintara.db')

        $-w = false # Sequel has warnings
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
        $-w = true if debug # Done with Sequel

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
                Dir.mkdir('var') unless Dir.exists?('Dir')
                self.logger = Logger.new('var/kintara.log', 'weekly')
            end
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"

            # Set up logging
            self.logger = Logger.new($stdout) if logging or debug
        end

        if debug
            @@db.loggers << @logger
            log_level = :debug
        else
            log_level = @@config.log_level.to_sym
        end

        self.log_level = log_level if logging

        #u = DB::User.new
        #u.node = 'rakaur'
        #u.domain = 'malkier.net'
        #u.password = Digest::MD5.hexdigest('partypants')
        #u.save

        # Write the PID file
        Dir.mkdir('var') unless File.exists?('var')
        File.open('var/kintara.pid', 'w') { |f| f.puts(Process.pid) }

        # XXX - timers

        # Start the listeners
        @@config.listeners.each do |listener|
            @@servers << XMPP::Server.new do |s|
                s.bind_to = listener.bind_to
                s.port    = listener.port
                s.type    = listener.kind.to_sym

                s.logger  = @logger if logging
            end
        end

        Thread.abort_on_exception = true if debug

        @@servers.each { |s| s.thread = Thread.new { s.io_loop } }
        @@servers.each { |s| s.thread.join }

        # Exiting...
        app_exit

        # Return...
        self
    end

    ######
    public
    ######

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

    # Converts a Hash into a Hash that allows lookup by String or Symbol
    def indifferent_hash(hash)
        # Hash.new blocks catch lookup failures
        hash = Hash.new do |hash, key|
                   hash[key.to_s] if key.is_a?(Symbol)
               end.merge(hash)

        # Look for any hashes inside the hash to convert
        hash.each do |key, value|
            # Convert this subhash
            hash[key] = indifferent_hash(value) if value.is_a?(Hash)

            # Arrays could have hashes in them
            value.each_with_index do |arval, index|
                hash[key][index] = indifferent_hash(arval) if arval.is_a?(Hash)
            end if value.is_a?(Array)
        end
    end

    def app_exit
        @logger.close if @logger
        File.delete('var/kintara.pid')
        exit
    end
end

