# encoding: utf-8
module OffsitePayments#:nodoc:
  module Integrations #:nodoc:
    # http://www.tenpay.com
    module Tenpay

      mattr_accessor :service_url
      self.service_url = 'https://gw.tenpay.com/gateway/pay.htm'
      FIELDS_NOT_TO_BE_SIGNED = %w(sign)

      def self.return(post, options = {})
        Notification.new(post, options)
      end

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      # Generate the required signature as specified in the "sign_type" field that's passed in in the "fields" argument
      # TODO: Only 'MD5' is supported at this point
      def self.generate_signature(fields, key)
        #        log.debug("string to be signed by tenpay is #{signed_string(fields, key)}")
        #puts ("string to be signed by tenpay is #{signed_string(fields, key)}")
        case sign_type = fields["sign_type"]
        when 'MD5'
          Digest::MD5.hexdigest(signed_string(fields, key)).upcase
        when nil
          raise OffsitePayments::ActionViewHelperError, "'sign_type' must be specified in the fields"
        else
          raise OffsitePayments::ActionViewHelperError, "sign_type '#{sign_type}' not yet supported"
        end
      end

      # Generate the string to sign on from the fields. Currently Alipay doc specifies that the fields are arranged alphabetically.
      def self.signed_string(fields, key)
        fields.reject do |s|
          FIELDS_NOT_TO_BE_SIGNED.include?(s)
        end
        .sort.collect do |s|
          s[0]+"="+CGI.unescape(s[1])
          #s.join('=')
        end
        .join("&")+"&key=#{key}"
      end

      class Helper < OffsitePayments::Helper

        # protocol parameters
        mapping :service_version, 'service_version'
        mapping :charset, 'input_charset' # defaults to GBK
        mapping :sign_key_index, 'sign_key_index' # defaults to 1

        # business parameters
        mapping :body, 'body'
        mapping :notify_url, 'notify_url'
        mapping :return_url, 'return_url'
        mapping :partner, 'partner' # 10 digit number, like "120xxxxx"
        mapping :order, 'out_trade_no'
        mapping :total_fee, 'total_fee'
        # mapping :fee_type, 'fee_type' # defaults to 1, which is RMB
        mapping :remote_ip, 'spbill_create_ip' # browser IP

        # business paramters, optional
        # mapping :bank_type, 'bank_type'
        mapping :attach, 'attach'
        mapping :buyer_id, 'buyer_id'
        mapping :time_start, 'time_start'
        mapping :time_expire, 'time_expire'
        mapping :transport_fee, 'transport_fee'
        mapping :product_fee, 'product_fee'
        mapping :goods_tag, 'goods_tag'

        def initialize(order, account, options = {})
          #Rails.logger.debug  options.inspect
          @key = options.delete(:key) || "need key here"
          super
          self.partner = account
          add_field('bank_type', 'DEFAULT')
          add_field('fee_type', 1)
        end

        def sign
          #Rails.logger.info("8"*100)
          #add_field('sign_type', 'MD5')
          @fields['sign_type'] ||= 'MD5'
          add_field('sign', Tenpay.generate_signature(@fields, @key))
        end

        #this is for payment. only tested for create_direct_pay_by_user(即时到账)
        def redirect_url 
          sign if self.sign.nil?
          url = URI.parse(OffsitePayments::Integrations::Tenpay.service_url)
          # we don't use "to_query" here since that's a Rails functionality
          url.query = ( Rack::Utils.parse_nested_query(url.query).merge(self.form_fields) ).collect{|s|s[0]+"="+CGI.escape(s[1])}.join('&')
          url
        end

      end

      # contains functions to common to both "Notification" and "Return"
      module Common

        def status
          @params['trade_state']
        end

        # Verifies that the signature in the "sign" field is the same as would be generated with our "key"
        # Depends on the class has the @params and @key
        #   * @params the fields to be signed
        #   * @key the api key assigned by Alipay, corresponding to the "PID"
        def verify_signature
          #puts "sing in params: #{@params["sign"]}" unless @params["sign"] == Alipay.generate_signature(@params, @key)
          #puts Alipay.generate_signature(@params, @key)
          @params["sign"] == Tenpay.generate_signature(@params, @key)
        end

        def acknowledge
          verify_signature || raise(ActionViewHelperError, "Invalid Tenpay HTTP signature")
        end

        def has_all_required_fields?
          !self.class.const_defined?(:REQUIRED_FIELDS) || self.class::REQUIRED_FIELDS.all? {|f| params[f].present?}
        end

        # Parse the request query parameters into corresponding fields.
        # The key reason that the default Notification.parse() method is because, the "notify_id" field SHOULD NOT be unescaped first
        # There is no obvious documentation specifying this behavior, but the "return" URL generated by Alipay website calculates the
        # "sign" field based on the 'escaped' version of this field while other fields use the unescaped version
        def _bad_parse(post)
          @params ||= Hash.new
          @raw = post.to_s
          #puts ("-----parsing starts----") * 8
          for line in @raw.split('&')
            key, value = *line.scan( %r{^([A-Za-z0-9_.-]+)\=(.*)$} ).flatten
            if key.present?
              if self.class.const_defined?(:FIELDS_NOT_TO_BE_UNESCAPED_WHEN_PARSING) \
                && self.class::FIELDS_NOT_TO_BE_UNESCAPED_WHEN_PARSING.include?(key)
                params[key] = value.to_s
              else
                params[key] = CGI.unescape(value.to_s)
              end
            end
          end
          #puts ("-----parsing ends----") * 8
          @params
        end
      end

      # For Tenpay, Notification and Return contain same info
      class Notification < OffsitePayments::Notification
        include Common
        #       include Sign
        REQUIRED_FIELDS = %w(sign trade_mode trade_state partner bank_type total_fee fee_type notify_id transaction_id out_trade_no time_end)

        def initialize(post, options = {})
          if post.is_a? String
            super
          else
            @params = post
          end

          unless has_all_required_fields?
            msg = "in #{post.inspect}, requiring #{REQUIRED_FIELDS.sort.to_s} \n Getting #{params.keys.sort.to_s}"
            raise "Not valid Tenpay #{self.class}, because #{msg}"
          end
          #raise "Not valid Tenpay #{self.class}" unless has_all_required_fields?
          @key = options[:key] || raise(RuntimeError, "key not provided to generate signature")
        end

        def is_payment_complete?
          0 == trade_state
        end

        def pending?
          trade_status == 'WAIT_BUYER_PAY'
        end

        def status
          trade_status
        end

        def amount
          total_fee
        end

        def success?
          0 == trade_state
        end

        def message
          "#{out_trade_no},#{Money.new(amount*100, 'CNY')} => #{trade_status}"
        end

        %w(sign_type service_version input_charset sign pay_info partner bank_type bank_billno notify_id transaction_id out_trade_no attach buyer_alias).each do |param|
          self.class_eval <<-EOF
              def #{param}
                params['#{param}']
              end
              EOF
        end

        %w(time_end).each do |param|
          self.class_eval <<-EOF
              def #{param}
                Time.parse params['#{param}']
              end
              EOF
        end

        %w(sign_key_index trade_mode trade_state fee_type).each do |param| 
          self.class_eval <<-EOF
              def #{param}
                params['#{param}'].to_i
              end
              EOF
        end

        %w(total_fee transport_fee product_fee discount).each do |param|
          self.class_eval <<-EOF
             def #{param}
               Money.new(params['#{param}'].to_i, currency)
             end
             EOF
        end

        def currency
          case fee_type
          when 1;'CNY';
          else; raise 'unsupported currency'
          end
        end

        # Take the posted data and move the relevant data into a hash
        def parse(post)
          @params ||= Hash.new
          @raw = post
          for line in post.split('&')
            key, value = *line.scan( %r{^(\w+)\=(.*)$} ).flatten
            params[key] = CGI.unescape(value || '') if key.present?
            #puts "parsed #{key} => '#{value}', #{ key.present? ? 'aded' : 'NOT added' }"
          end
        end
      end
    end
end
end
