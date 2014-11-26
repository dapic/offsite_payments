# encoding: utf-8
#require 'wxpay/api_response'
module OffsitePayments#:nodoc:
  module Integrations #:nodoc:
    # http://mp.weixin.qq.com
    module Wxpay

      mattr_accessor :logger, :credentials
      mattr_reader :key

      UNIFIEDORDER_URL = 'https://api.mch.weixin.qq.com/pay/unifiedorder'
      ORDERQUERY_URL   = 'https://api.mch.weixin.qq.com/pay/orderquery'
      CLOSEORDER_URL   = 'https://api.mch.weixin.qq.com/pay/closeorder'
      REFUND_URL       = 'https://api.mch.weixin.qq.com/secapi/pay/refund'
      REFUNDQUERY_URL  = 'https://api.mch.weixin.qq.com/pay/refundquery'
      DOWNLOADBILL_URL = 'https://api.mch.weixin.qq.com/pay/downloadbill'
      SHORTURL_URL     = 'https://api.mch.weixin.qq.com/tools/shorturl'

      API_CONFIG = {
        unifiedorder: { request_url: 'https://api.mch.weixin.qq.com/pay/unifiedorder' },
        shorturl:     { request_url: 'https://api.mch.weixin.qq.com/tools/shorturl' },
      }
      FIELDS_NOT_TO_BE_SIGNED = %w(sign key)

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.generate_signature(fields)
        Digest::MD5.hexdigest(signed_string(fields)).upcase
      end

      # Generate the string to sign on from the fields. Current wxpay doc specifies that the fields are arranged alphabetically.
      def self.signed_string(fields)
        raise(RuntimeError, "key is need to generate the signature") unless self.key
        fields.reject {|s| FIELDS_NOT_TO_BE_SIGNED.include?(s)}
        .sort
        .collect {|s| s[0]+"="+CGI.unescape(s[1])}
        .join("&")+"&key=#{self.key}"
      end

      def self.credentials=(cred)
        @@key ||= cred.delete(:key)
        @@credentials = cred
      end

      module Common
        def has_all_required_fields?
          # logger.debug("required fields are #{self.class::REQUIRED_FIELDS.inspect}")
          # logger.debug("has fields #{params}")
          !self.class.const_defined?(:REQUIRED_FIELDS) ||
            self.class::REQUIRED_FIELDS.all? {|f| params[f].present?}
        end

        def logger
          Wxpay.logger
        end

        def params
          @params ||= @fields
        end

        def verify_signature
          @params["sign"] == Wxpay.generate_signature(@params)
        end

        def acknowledge
          verify_signature || raise(ActionViewHelperError, "Invalid Wxpay HTTP signature")
        end

        def to_xml
          Nokogiri::XML::Builder.new do |x|
            x.xml {
              form_fields.each {|k,v|
                x.send(k) { x.cdata(v) }
              }
            }
          end
          .to_xml
        end
      end

      module CommonHelper
        def load_data(biz_data)
          @fields = {}
          Wxpay.credentials.each { |k,v| add_field(k,v)}
          biz_data.each { |k,v| add_field(k,v) }
          unless has_all_required_fields?
            msg = "Requiring #{REQUIRED_FIELDS.sort.to_s} \n Getting #{Wxpay.credentials.merge(biz_data).keys.map(&:to_s).sort.to_s}"
            raise "Not valid #{self.class.name}, because #{msg}"
          end
        end

        def sign
          params['nonce_str'] || add_field('nonce_str', SecureRandom.hex) 
          add_field('sign', Wxpay.generate_signature(@fields))
        end

        def process
          post_response = ssl_post(API_CONFIG[API_REQUEST][:request_url], self.to_xml)
          logger.debug("got response from wxpay: #{post_response.inspect}")
          @response = ApiResponse.parse_response(API_REQUEST, post_response)
          throw :done, [:comm_failure, @response.return_code] unless @response.comm_success?
          throw :done, [:credential_mismatch_failure, @response.params] unless @response.credentials_match?(params)
          throw :done, :unverifiable_response unless @response.acknowledge
          throw :done, [:biz_failure, @response.error_code, @response.error_des] unless @response.biz_success?
          throw :done, @response.params
        end
      end

      class UnifiedOrderHelper < ::OffsitePayments::Helper 
        include Common
        include CommonHelper
        REQUIRED_FIELDS = %w(body out_trade_no total_fee spbill_create_ip notify_url trade_type) 
        API_REQUEST = :unifiedorder
        def initialize(data)
          load_data(data)
        end
      end

      class ShortUrlHelper < ::OffsitePayments::Helper
        include Common
        include CommonHelper
        REQUIRED_FIELDS = %w(long_url) 
        API_REQUEST = :shorturl
        def initialize(data)
          load_data(data)
        end
      end

      class BaseResponse
        include Common
        require 'nokogiri'
        attr_reader :params
        REQUIRED_FIELDS = %w(return_code)
        REQUIRED_RETURN_CREDENTIAILS = %w(appid mch_id)
        def initialize(http_response, options = {})
          resp_xml = Nokogiri::XML(http_response.body.gsub(/\n/,'').gsub(/>\s*</, "><"))
          @params = {}

          #logger.debug("resp_xml is #{resp_xml.to_xml}")
          #logger.debug("resp_is #{resp_xml.to_s}")
          #logger.debug('')
          resp_xml.xpath("//xml").children.each {|a|
            logger.debug("assigning #{a.name} to #{a.content}")
            @params[a.name] = a.content 
          }
          raise "Not valid #{self.class.name}" unless has_all_required_fields?
        end

        def comm_success?
          'SUCCESS' == @params['return_code']
        end

        def comm_failure_msg
          @params['return_msg']
        end

        def credentials_match?(expected_cred)
          REQUIRED_RETURN_CREDENTIAILS.all? { |p| @params[p] == expected_cred[p] } 
        end

        def biz_success?
          'SUCCESS' == @params['result_code']
        end

        def biz_failure_code
          @params['err_code']
        end

        def biz_failure_desc
          @params['err_code_des'] || "This PDU does not contain error description"
        end
      end

      # For Wxpay, there is only Notification. No "Return"
      class Notification < BaseResponse
        include Common
        REQUIRED_FIELDS_BIZ_SUCCESS = %w(openid is_subscribe trade_type bank_type total_fee transaction_id out_trade_no time_end)

        def amount
          total_fee
        end

        def currency
          fee_type
        end

        %w(openid is_subscribe trade_type bank_type fee_type transaction_id out_trade_no attach).each do |param|
          self.class_eval <<-EOF
            def #{param}
              params['#{param}']
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

        %w(time_end).each do |param|
          self.class_eval <<-EOF
            def #{param}
              Time.parse params['#{param}']
            end
            EOF
        end
      end

      module ApiResponse
        def self.parse_response(api_request, http_response)
          case api_request
          when :unifiedorder; UnifiedOrderResponse.new(http_response);
          when :shorturl; ShortUrlResponse.new(http_response);
          else raise "UnSupported Wxpay API request #{api_request.to_s}";
          end
        end

        class UnifiedOrderResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(trade_type prepay_id)

          def pay_url
            code_url
          end

          %w(trade_type prepay_id code_url).each do |param|
            self.class_eval <<-EOF
            def #{param}
              params['#{param}']
            end
            EOF
          end
        end

        class ShortUrlResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(short_url)
          %w(short_url).each do |param|
            self.class_eval <<-EOF
            def #{param}
              params['#{param}']
            end
            EOF
          end
        end
      end

    end
end
end
