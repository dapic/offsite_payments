# encoding: utf-8
#require 'wxpay/api_response'
module OffsitePayments#:nodoc:
  module Integrations #:nodoc:
    # http://mp.weixin.qq.com
    # This module contains the communication layer. It should not make business decisions
    module Wxpay

      class CommunicationError < RuntimeError; end
      class CredentialMismatchError < RuntimeError; end
      class UnVerifiableResponseError < RuntimeError; end
      class BusinessError < RuntimeError; end
      mattr_accessor :logger, :credentials
      mattr_reader :key, :appsecret

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
        orderquery:   { request_url: 'https://api.mch.weixin.qq.com/pay/orderquery'},
      }
      FIELDS_NOT_TO_BE_SIGNED = %w(sign key)

      MONEY_FIELDS   = %w(total_fee coupon_fee)
      TIME_FIELDS    = %w(time_start time_expire time_end)

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.generate_signature(fields)
        #logger.debug("fields are #{fields.inspect}")
        #logger.debug("signed_string are #{signed_string(fields)}")

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
        @@key         = cred.delete(:key)
        @@appsecret   = cred.delete(:appsecret)
        @@credentials = cred
      end

      def self.logger
        @@logger ||= Logger.new(STDOUT)
      end

      module Common
        def has_all_required_fields?
          # logger.debug("required fields are #{self.class::REQUIRED_FIELDS.inspect}")
          # logger.debug("has fields #{params}")
          !self.class.const_defined?(:REQUIRED_FIELDS) ||
            self.class::REQUIRED_FIELDS.all? {|f| params[f].present?}
        end

        def params
          @params ||= @fields
        end

        def verify_signature
          (@params["sign"] == Wxpay.generate_signature(@params))
          .tap {|r| Wxpay.logger.debug("#{__LINE__}: Got signature #{@params["sign"]} while expecting #{Wxpay.generate_signature(@params)}.") unless r }
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
          self.class.logger = Wxpay.logger
        end

        def sign
          params['nonce_str'] || add_field('nonce_str', SecureRandom.hex) 
          add_field('sign', Wxpay.generate_signature(@fields))
        end

        def process
          Wxpay.logger.info("logger level is set to #{Wxpay.logger.level} <==")
          Wxpay.logger.debug("sending to #{API_CONFIG[self.class::API_REQUEST][:request_url]}")
          Wxpay.logger.debug("payload is #{self.to_xml}")

          post_response = ssl_post(API_CONFIG[self.class::API_REQUEST][:request_url], self.to_xml)
          Wxpay.logger.debug("got response from wxpay: #{post_response.inspect}")
          @response = ApiResponse.parse_response(self.class::API_REQUEST, post_response)
          raise CommunicationError, @response.return_code unless @response.comm_success?
          raise CredentialMismatchError unless @response.credentials_match?(params)
          raise UnVerifiableResponseError  unless @response.acknowledge
          @response #let somebody upstream handle the biz logic
        end
      end

      # These helper need to inherit from OffsitePayments::Helper therefore has to have CommomHelper mixed in
      class UnifiedOrderHelper < ::OffsitePayments::Helper 
        include Common
        include CommonHelper
        include ActiveMerchant::PostsData
        REQUIRED_FIELDS = %w(body out_trade_no total_fee spbill_create_ip notify_url trade_type) 
        API_REQUEST = :unifiedorder
        def initialize(data)
          load_data(data)
        end
      end

      class OrderQueryHelper < ::OffsitePayments::Helper
        include Common
        include CommonHelper
        include ActiveMerchant::PostsData
        REQUIRED_FIELDS = %w(out_trade_no) 
        API_REQUEST = :orderquery
        def initialize(data)
          load_data(data)
        end
      end
      
      class ShortUrlHelper < ::OffsitePayments::Helper
        include Common
        include CommonHelper
        include ActiveMerchant::PostsData
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

        def self.setup_fields(fields)
          (fields).each do |param|
            case 
            when MONEY_FIELDS.include?(param)  
              self.class_eval <<-EOF
               def #{param}
                 Money.new(params['#{param}'].to_i, currency)
               end
             EOF
            when TIME_FIELDS.include?(param)
              self.class_eval <<-EOF
                def #{param}
                  Time.parse params['#{param}']
                end
              EOF
            else
              self.class_eval <<-EOF
                def #{param}
                  params['#{param}']
                end
            EOF
            end
          end
        end

        def initialize(http_response, options = {})
          Wxpay.logger.debug("response is #{http_response}")
          resp_xml = Nokogiri::XML(http_response.gsub(/\n/,'').gsub(/>\s*</, "><"))
          @params = {}

          #logger.debug("resp_xml is #{resp_xml.to_xml}")
          #logger.debug("resp_is #{resp_xml.to_s}")
          #logger.debug('')
          resp_xml.xpath("//xml").children.each {|a|
            #logger.debug("assigning #{a.name} to #{a.content}")
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
        OPTIONAL_FIELDS_BIZ_SUCCESS = %w(coupon_fee fee_type attach return_msg)
        BaseResponse.setup_fields(REQUIRED_FIELDS_BIZ_SUCCESS + OPTIONAL_FIELDS_BIZ_SUCCESS)
        alias_method :amount, :total_fee
        alias_method :currency, :fee_type
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
          OPTIONAL_FIELDS_BIZ_SUCCESS = %w(code_url)
          BaseResponse.setup_fields(REQUIRED_FIELDS_BIZ_SUCCESS + OPTIONAL_FIELDS_BIZ_SUCCESS)
          alias_method :pay_url, :code_url
        end

        class OrderQueryResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(trade_state openid is_subscribe trade_type bank_type total_fee time_end)
          OPTIONAL_FIELDS_BIZ_SUCCESS = %w(device_info coupone_fee fee_type transaction_id out_trade_no attach)
          BaseResponse.setup_fields(REQUIRED_FIELDS_BIZ_SUCCESS + OPTIONAL_FIELDS_BIZ_SUCCESS)
        end

        class ShortUrlResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(short_url)
          OPTIONAL_FIELDS_BIZ_SUCCESS = []
          BaseResponse.setup_fields(REQUIRED_FIELDS_BIZ_SUCCESS + OPTIONAL_FIELDS_BIZ_SUCCESS)
        end
      end

    end
end
end
