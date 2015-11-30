require 'json'

module Lita
  module Handlers
    class Stackstorm < Handler
      # insert handler code here

      config :url, required: true
      config :username, required: true
      config :password, required: true

      class << self
        attr_accessor :token, :expires
      end

      def self.config(config)
        self.token = nil
        self.expires = nil
      end

      route /^st2 login$/, :login, command: false, help: { "st2 login" => "login with st2-api" }
      route /^st2 list$/, :list, command: false, help: { "st2 list" => "list available st2 chatops commands" }

      route /^!(.*)$/, :call_alias, command: false, help: {}

      def authenticate
        resp = http.post("#{config.url}:9100/v1/tokens") do |req|
          req.body = {}
          req.headers['Authorization'] = http.set_authorization_header(:basic_auth, config.username, config.password)
        end
        self.class.token = JSON.parse(resp.body)['token']
        self.class.expires = JSON.parse(resp.body)['expiry']
        resp
      end

      def call_alias(msg)
        if expired
          authenticate
        end
        command_array = msg.matches.flatten.first.split
        candidates = redis.scan_each(:match => "#{command_array[0..1].join(' ')}*")
        p = candidates.take_while {|i| i.split.length == command_array.length}
        l = candidates.take_while {|i| i.split.length > command_array.length}
        if p.length == 1
          payload = {
            name: command_array[0..1].join('_'),
            format: "#{command_array[0..1].join(' ')} {{pack}}",
            command: msg,
            user: msg.user,
            source_channel: 'chatops',
            notification_channel: 'lita'
          }
          s = make_post_request(":9999/v1/aliasexecution", payload)
          msg.reply "#{config.url}:9999/#/history/#{s.body.to_s[1..-2]}/general"
        elsif l.length > 0
          response_text = "possible matches:"
          l.each do |match|
            response_text+= "\n\t#{match}"
          end
          msg.reply response_text
        else
          msg.reply "Failed! No Aliases Found..."
        end
      end

      def list(msg)
        if expired
          authenticate
        end
        s = make_request(":9999/v1/actionalias", "")
        if JSON.parse(s.body).empty?
          msg.reply "No Action Aliases Registered"
        else
          j = JSON.parse(s.body)
          a = ""
          j.take_while{|i| i['enabled'] }.each do |command|
            command['formats'].each do |format|
              redis.set(format, command['action_ref'])
              a+= "#{format} -> #{command['action_ref']}\n"
            end
          end
          msg.reply a
        end
      end

      def login(msg)
        http_resp = authenticate
        if ![200, 201, 280].index(http_resp.status).nil?
          msg.reply "login successful\ntoken: #{self.class.token}"
        elsif http_resp.status == 500
          msg.reply "#{http_resp.status}: login failed!!"
        else
          msg.reply "#{http_resp.status}: login failed!!"
        end
      end

      def expired
        self.class.token.nil? || Time.now >= Time.parse(self.class.expires)
      end

      def make_request(path, body)
        resp = http.get("#{config.url}#{path}") do |req|
          req.body = {}
          req.headers = headers
          req.body = body.to_json
        end
        resp
      end

      def make_post_request(path, body)
        resp = http.post("#{config.url}#{path}") do |req|
          req.body = {}
          req.headers = headers
          req.body = body.to_json
        end
        resp
      end


      def headers
        headers = {}
        headers['Content-Type'] = 'application/json'
        headers['X-Auth-Token'] = "#{self.class.token}"
        headers
      end

      Lita.register_handler(self)
    end
  end
end
