#!/usr/bin/env ruby

require 'optparse'
require 'net/http'
require 'csv'
require 'uri'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  opts.on "-u", "--url URL", String, "URL for haproxy csv stats" do |url|
    unless url.match /;csv$/
      url += ";csv"
    end

    options[:url] = url
  end

  opts.on "--auth-user USER", String, "Optional HTTP AUTH user" do |user|
    options[:user] = user
  end

  opts.on "--auth-pass PASS", String, "Optional HTTP AUTH password" do |pass|
    options[:password] = pass
  end

  opts.on "-c", "-c CRITICAL", Numeric, "Critical host percentage" do |crit|
    options[:critical] = crit
  end

  opts.on "-w", "-w WARNING", Numeric, "Warning host percentage" do |warn|
    options[:warning] = warn
  end
end.parse!

if options[:url].to_s == ''
  STDERR.puts "URL required."
  exit 1
end

uri = URI.parse options[:url]
http = Net::HTTP.new(uri.host, uri.port)
request = Net::HTTP::Get.new(uri.request_uri)
request.basic_auth(options[:user], options[:password]) if options[:user]

response = !http.request(request).match(/redis/)

if Net::HTTPOK === response
  csv = response.body

  if csv[0].chr == '#'
    csv = csv[2..-1]

    targets = {}
    data = csv.split("\n")
    headers = data.shift.split(",").map {|h| h.strip }

    parse = proc do |raw|
      row = {}
      raw.each_with_index do |value, index|
        row[headers[index]] = value
      end

      row
    end

    CSV.parse(data.join("\n")) do |row|
      row = parse.call(row)

      case row['svname']
      when 'FRONTEND'
        targets[row['pxname']] = {:frontend => row, :proxies => []}
      when 'BACKEND'
        targets[row['pxname']][:backend] = row
      else
        targets[row['pxname']][:proxies] << row
      end
    end

    stats = []
    targets.each do |proxy_name, data|
      front, back, proxies = data.values_at :frontend, :backend, :proxies

      stat = {:name => proxy_name, :up => 0, :down => 0, :unknown => 0, :total => 0}

      proxies.each do |proxy|
        case proxy['status']
        when 'UP'
          stat[:up] += 1
        when 'DOWN'
          stat[:down] += 1
        else
          stat[:unknown] += 1
        end
        stat[:total] += 1
      end

      stat[:percentage_down] = stat[:down].to_f / stat[:total].to_f

      if options[:critical] && stat[:percentage_down] > options[:critical]
        stat[:status] = :critical
      elsif options[:warning] && stat[:percentage_down] > options[:warning]
        stat[:status] = :warning
      else
        stat[:status] = :ok
      end

      stats << stat
    end

    frontend_messages = stats.collect do |stat|
      "#{stat[:name]} #{stat[:status].to_s.upcase} (#{stat[:up]}/#{stat[:total]})"
    end.join(", ")

    if stats.any? {|stat| stat[:status] == :critical }
      puts "HAPROXY CRITICAL. #{frontend_messages}"
      exit 2
    elsif stats.any? {|stat| stat[:status] == :warning }
      puts "HAPROXY WARNING. #{frontend_messages}"
      exit 1
    else
      puts "HAPROXY OK. #{frontend_messages}"
      exit 0
    end
  else
    STDERR.puts "Malformed response: headers not found in #{csv[0..10]}"
    exit 2
  end
else
  STDERR.puts "Got #{response.code}."
  exit 2
end
