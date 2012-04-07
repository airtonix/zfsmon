require 'sinatra'
require 'data_mapper'
require 'yaml'

DataMapper::Logger.new(STDOUT, :debug)
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/zfsdata.db")

require "#{File.dirname(__FILE__)}/zfsmon_data_objects"
require "#{File.dirname(__FILE__)}/zfs_utils"

DataMapper.finalize.auto_upgrade!

def get_host_record( hostget )
    if hostget.is_int?
        @host = ZFSHost.get hostget.to_i
    else
        @host = ZFSHost.first :hostname => hostget
    end
    return @host
end

def get_pool_record( hostrec, pool )
    hostrec.pools.first_or_create :host => hostrec, :name => pool
end

def host_not_found( request="" )
    status 404
    "The provided host ID or hostname " + request.to_s + " could not be found in the database."
end

def pool_not_found( request="" )
    status 404
    "The provided pool ID or name " + request.to_s + " could not be found in the database."
end

get '/' do
    erb :index
end


# Host-level operations
get '/:host/?' do
    @host = get_host_record params[:host]
    if @host
        "Hostname: #{@host.hostname}\nDescription: #{@host.hostdescription}\nLast Updated: #{@host.lastupdate.to_s}"
    else
        host_not_found params[:host]
    end
end

post '/:host/?' do
    puts params[:host]
    puts request.body.read
    @host = get_host_record params[:host]
    if not @host
        z = ZFSHost.create( :hostname => params[:hostname],
                            :hostdescription => params[:hostdescription],
                            :lastupdate => Time.now )
        if not z.saved?
            status 503
            'DM was unable to create a new host record in the database.'
            z.errors.each do |e|
                puts e
            end
        else
            status 201
            "Succesfully created a new host record for " + params[:hostname]
        end
    else
        @host.update( :hostdescription => params[:hostdescription],
                      :lastupdate => Time.now )
        status 200
        "The host record for " + params[:hostname] + " was succesfully updated."
    end
end

get '/:host/pools/?' do
    @host = get_host_record params[:host]
    "Host: #{@host.hostname}\nPools: #{@host.pools.length.to_s}"
end

get '/:host/pools/:pool/?' do
    @host = get_host_record params[:host]
    if not @host
        host_not_found params[:host]
    end
    @pool = get_pool_record @host, params[:pool]
    if not @pool
        status 404
        "The requested pool could not be found on " + params[:hostname] + "."
    end
    erb :poolview
end

post '/:host/pools/:pool/?' do
    @host = get_host_record params[:host]
    if not @host
        host_not_found params[:host]
    end

    @pool = get_pool_record @host, params[:pool]

    request.POST.each do |k, v|
        if not $ZFS_POOL_FIELDS.include? k
            next
        else
            if $ZFS_POOL_SIZE_FIELDS.include? k
                v = v.to_i
            end
            
            if $ZFS_ENUM_FIELDS.include? k
                v = v.downcase
            end

            # GUIDs sometimes get parsed as integers..
            # It's easier just to convert them back here.
            if k == 'guid'
                v = v.to_s
            end

            # ZFS returns 'on' and 'off' for certain fields but DM expects
            # boolean values.
            if v == 'on'
                v = true
            elsif v == 'off'
                v = false
            end

            # Cap is a percentage for some reason
            if k == 'cap'
                v = v[0..-1].to_i / 100
            end

            # Dedup is a float but ZFS puts an 'x' on the end
            if k == 'dedup'
                v = v[0..-1].to_f
            end
            @pool.attribute_set k.to_sym, v
        end
    end
    @pool.attribute_set :host, @host
    if @pool.dirty?
        @pool.attributes :lastupdate => Time.now
        @pool.save
    else
        puts "not saving #{@pool.name}"
    end
end
