# encoding: utf-8
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module AlipayWap

      mattr_accessor :service_url, :logger, :credentials, :options
      @@service_url = 'http://wappaygw.alipay.com/service/rest.htm'
      @@options = {
          _input_charset: 'utf-8',
          sign_type: 'MD5',
      }
      TIME_FIELDS = %w(gmt_create gmt_payment gmt_close gmt_refund notify_time )

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(post, options = {})
        Return.new(post, options )
      end

      def self.logger
        @@logger ||= (require 'logger'; Logger.new(STDOUT))
      end

      module Common
        def assemble_request_params(param_fields)
          param_fields.collect { |s| "#{s[0]}=#{CGI.escape(s[1].to_s)}" }.join('&')
        end
      end

      module AttributesHelper
        def self.included(klass)
          fields = []
          fields += klass::PAYLOAD_DATA_FIELDS if klass.const_defined?(:PAYLOAD_DATA_FIELDS)
         # fields += klass::OPTIONAL_FIELDS_BIZ_SUCCESS if klass.const_defined?(:OPTIONAL_FIELDS_BIZ_SUCCESS)

          fields.each do |param|
            case
              when TIME_FIELDS.include?(param)
                klass.class_eval <<-EOF
                def #{param}
                  Time.parse payload_fields['#{param}']
                end
                EOF
              else
                klass.class_eval <<-EOF
                def #{param}
                  payload_fields['#{param}']
                end
                EOF
            end
          end
        end
      end

      module RequestCommon
        # request_fields = protocol_fields + payload_xml
        def request_fields
          @protocol_fields.merge({'req_data' => payload_xml(@payload_fields)})
        end
      end

      module CredentialHelper
        def key;
          @key ||= AlipayWap.credentials[:key];
        end

        def partner;
          AlipayWap.credentials[:pid].to_s;
        end

        def seller_email;
          AlipayWap.credentials[:seller][:email];
        end
      end

      module SignatureProcessor
        FIELDS_NOT_TO_BE_SIGNED = 'sign sign_type'

        def sign
          @protocol_fields['sign'] ||= generate_signature
        end

        def generate_signature
          case sign_type = (@protocol_fields['sec_id'] || AlipayWap.options[:sign_type])
            when 'MD5'
              Digest::MD5.hexdigest(signed_string)
                   .tap { |r| AlipayWap.logger.debug("signature '#{r}' generated from signed_string '#{signed_string}'") }
            when '0001' #RSA
              raise NotImplementedError, "sign_type '0001' -> RSA not yet supported"
            when nil
              raise ArgumentError, "'sign_type' must be specified in the fields or in module options"
            else
              raise NotImplementedError, "sign_type '#{sign_type}' not yet supported"
          end
        end

        # Generate the string to sign on from all in @request_fields.
        # Currently Alipay doc specifies that the fields are arranged alphabetically except for data sent to "notify_url"
        def signed_string
          signed_data_only = request_fields.reject { |s| FIELDS_NOT_TO_BE_SIGNED.include?(s) }
          signed_data_only.sort.collect { |s| "#{s[0]}=#{s[1]}" }.join('&') + key
        end

        def acknowledge
          (request_fields['sign'] == generate_signature) || raise(SecurityError, "Invalid Alipay HTTP signature in #{self.class}")
        end
      end

      #depends on the "payload" method
      module OutgoingRequestProcessor
        def process
          AlipayWap.logger.debug "post payload is #{post_payload}"
          @post_response = ssl_post(AlipayWap.service_url, post_payload)
          AlipayWap.logger.debug "post response is #{@post_response}"
          @response = parse_response
        end

        def parse_response
          case
            when self.is_a?(CreateDirectHelper)
              CreateDirectResponse.new(@post_response, self)
            else
              raise "response class for #{self.class.name} not defined/implemented yet"
          end
        end

      end

      class CreateDirectHelper #< OffsitePayments::Helper
        include Common
        include RequestCommon
        include CredentialHelper
        include SignatureProcessor
        include OutgoingRequestProcessor
        include ActiveMerchant::PostsData

        attr_accessor :protocol_fields, :payload_fields

        PROTOCOL_STATIC_FIELDS = {

            'service' => 'alipay.wap.trade.create.direct',
            'format'  => 'xml',
            'v'       => '2.0',
        }

        def initialize(biz_data)
          @payload_fields = biz_data.merge(seller_account_name: seller_email)
          @protocol_fields = PROTOCOL_STATIC_FIELDS.merge(
              {
                  # '_input_charset' => AlipayWap.options[:_input_charset],
                  'partner' => partner,
                  'sec_id'  => AlipayWap.options[:sign_type],
                  'req_id'  => SecureRandom.hex(16).to_s,
              })
          sign
        end

        def payload_xml(biz_data)
          xml = biz_data.map { |k, v| "<#{k}>#{v.to_s.encode(:xml => :text)}</#{k}>" }.join
          "<direct_trade_create_req>#{xml}</direct_trade_create_req>"
        end

        def post_payload
          assemble_request_params(request_fields.sort)
        end
      end

      class CreateDirectResponse
        require 'nokogiri'
        include CredentialHelper
        include SignatureProcessor
        attr_reader :request_token, :error

        # ignore_signature_check should be used in testing only!
        def initialize(raw_response, req, ignore_signature_check = false)
          @raw_response, @request = raw_response, req
          parse ignore_signature_check
        end

        def parse(ignore_signature_check)
          raise TypeError unless @raw_response.is_a? String
          @raw_fields = @raw_response.split('&').inject({}) { |h, kv| k, v = kv.split('=', 2); h[k] = CGI.unescape(v); h }
          @protocol_fields = @raw_fields
          credential_check

          case
            when @protocol_fields.has_key?('res_data')
              acknowledge unless ignore_signature_check
              @request_token = Nokogiri::XML(@protocol_fields.delete('res_data')).at_xpath('//request_token').content
            when @protocol_fields.has_key?('res_error')
              @error = Nokogiri::XML(@protocol_fields.delete('res_error')).xpath('//err').children.inject({}) do |h, node|
                h[node.name] = node.content.strip; h
              end
            else
              raise "Invalid response format for #{self.class}"
          end
        end

        # verify if this response is for this request
        def credential_check
          %w(partner req_id service v).all? { |k|
             # AlipayWap.logger.debug "#{k}: #{@protocol_fields[k]}<->#{@request.protocol_fields[k]}"
            @protocol_fields[k] == @request.protocol_fields[k].to_s
          } || raise("Response is not for this request")
        end

        def request_fields
          @raw_fields
        end
      end

      class AuthAndExecuteHelper # < OffsitePayments::Helper
        include Common
        include RequestCommon
        include CredentialHelper
        include SignatureProcessor
        attr_accessor :protocol_fields, :payload_fields

        PROTOCOL_STATIC_FIELDS = {
            'service' => 'alipay.wap.auth.authAndExecute',
            'format'  => 'xml',
            'v'       => '2.0',
        }

        def initialize(biz_data)
          @payload_fields = biz_data
          @protocol_fields = PROTOCOL_STATIC_FIELDS.merge(
              {
                  '_input_charset' => AlipayWap.options[:_input_charset],
                  'sec_id' => AlipayWap.options[:sign_type],
                  'partner' => partner,
              })
          sign
        end

        def payload_xml(biz_data)
          xml = biz_data.map { |k, v| "<#{k}>#{v.encode(:xml => :text)}</#{k}>" }.join
          "<auth_and_execute_req>#{xml}</auth_and_execute_req>"
        end

        def request_url
          url = URI.parse(AlipayWap.service_url)
          url.query = assemble_request_params(
              request_fields.merge(Rack::Utils.parse_nested_query(url.query))
          )
          url.to_s
        end
      end

      class Return < ::OffsitePayments::Return
        PAYLOAD_DATA_FIELDS = %w(out_trade_no trade_no request_token)
        include Common
        include CredentialHelper
        include AttributesHelper
        include SignatureProcessor
        attr_accessor :payload_fields
        alias_method :request_fields, :params

        def initialize(request_string, opts = {})
          super
          @key = opts[:key]
          protocol_parse
        end

        def protocol_parse
          @protocol_fields = @params.reject {|k,v| PAYLOAD_DATA_FIELDS.include? k}
          @payload_fields = @params.select {|k,v| PAYLOAD_DATA_FIELDS.include? k}
        end

        def success?
          'success' == @protocol_fields['result']
        end

      end

      class Notification < OffsitePayments::Notification
        PAYLOAD_DATA_FIELDS = %w(payment_type subject trade_no buyer_email gmt_create notify_type out_trade_no
          notify_time seller_id trade_status is_total_fee_adjust total_fee gmt_payment seller_email gmt_close
          price buyer_id notify_id use_coupon refund_status gmt_refund)

        include RequestCommon
        include CredentialHelper
        include AttributesHelper
        include SignatureProcessor
        attr_accessor :protocol_fields, :payload_fields

        alias_method :request_fields, :params
        alias_method :gross, :total_fee
        alias_method :status, :trade_status
        alias_method :transaction_id, :trade_no

        def initialize(request_string, opts = {})
          super
          @key = opts[:key]
          protocol_parse
        end

        def protocol_parse
          @protocol_fields = @params.clone
          @payload_fields = Nokogiri::XML(@protocol_fields.delete('notify_data')).xpath('//notify').children.inject({}) do |h, node|
            h[node.name] = node.content.strip; h
          end
        end

        def currency
          'CNY'
        end

        def success?
          %w(TRADE_FINISHED TRADE_SUCCESS).include? status
        end

        # this order is explicitly set. the Doc is kinda vague but this is found through trial-and-error
        def signed_string
          "service=#{params['service']}&v=#{params['v']}&sec_id=#{params['sec_id']}&notify_data=#{params['notify_data']}#{key}"
        end
      end

    end

  end #
end
