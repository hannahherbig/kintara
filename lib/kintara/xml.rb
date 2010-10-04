#
# kintara: malkier xmpp server
# lib/kintara/xml.rb: random XML generation, etc
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(rexml/document).each { |m| require m }

# Import required application modules
#%w().each { |m| require m }

module XML
    extend self

    def new_element(name, namespace = nil)
        elem = REXML::Element.new(name)
        elem.add_namespace(namespace) if namespace

        elem
    end

    XID_RE = /
             ^              # beginning of string
             (?:            # non-capturing group
                 ([^@\/]+)@ # anything-but-slash|@ followed by @
             )?             # close non-capturing, ? makes it optional
             ([^\/@]+)      # always grab anything-but-slash|@
             \/?            # optional slash
             (?:            # non-capturing group
                 ([^\/@]+)  # optional anything-but-slash|@
             )              # close non-capturing group
             $              # end of string
             /x

    def split_xid(xid)
        XID_RE.match(xid).captures
    end

    def valid_xid?(xid)
        XID_RE.match(xid)
    end

    # Generate a unique stream id.
    # I think I yanked this from a Google SoC project.
    #
    # return:: [String] random string
    #
    @@id_counter = 0
    @@id_changed = 0

    def new_id
        @@id_changed = Time.now.to_i

        time          = Time.now.to_i
        tid           = String.new { }.object_id
        @@id_counter += 1

        nid = (time << 48) | (tid << 16) | @@id_counter
        id  = ''

        while nid > 0
            id   += (nid & 0xFF).chr
            nid >>= 8
        end

        unless @@id_changed == time
            @@id_changed = time
            @@id_counter = 0
        end

        [id].pack('m').strip
    end

end # module XML
