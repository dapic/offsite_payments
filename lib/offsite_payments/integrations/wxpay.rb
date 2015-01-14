# encoding: utf-8
#require 'wxpay/api_response'
require 'weixin_authorize'
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
      mattr_reader :key, :appsecret, :auth_client

      FIELDS_NOT_TO_BE_SIGNED = %w(sign key)

      MONEY_FIELDS   = %w(total_fee coupon_fee cash_fee)
      TIME_FIELDS    = %w(time_start time_expire time_end)

      # helper classes are defined later, so we have to use symbols here. if we use constants, like 'UnifiedOrderHelper' instead of ':UnifiedOrderHelper', Ruby would complain
      API_CONFIG = {
        unifiedorder: { helper_type: :UnifiedOrderHelper , request_url: 'https://api.mch.weixin.qq.com/pay/unifiedorder' } ,
        orderquery:   { helper_type: :OrderQueryHelper   , request_url: 'https://api.mch.weixin.qq.com/pay/orderquery'}    ,
        closeorder:   { helper_type: :CloseOrderHelper   , request_url: 'https://api.mch.weixin.qq.com/pay/closeorder'}    ,
        refund:       { helper_type: :RefundHelper       , request_url: 'https://api.mch.weixin.qq.com/secapi/pay/refund'} ,
        refundquery:  { helper_type: :RefundQueryHelper  , request_url: 'https://api.mch.weixin.qq.com/pay/refundquery'}   ,
        downloadbill: { helper_type: :DownloadBillHelper , request_url: 'https://api.mch.weixin.qq.com/pay/downloadbill'}  ,
        shorturl:     { helper_type: :ShortUrlHelper     , request_url: 'https://api.mch.weixin.qq.com/tools/shorturl' }   ,
        get_brand_wcpay: { helper_type: :GetBrandWCPayHelper, request_url: '' }   ,
      }

      def self.get_helper(api_type, data)
        self.const_get(API_CONFIG[api_type][:helper_type]).new(data)
      end

      def self.notification(post, options = {})
        Notification.new(self.parse_xml(post), options)
      end

      def self.parse_xml(http_response)
          resp_xml = Nokogiri::XML(http_response.gsub(/\n/,'').gsub(/>\s*</, "><"))
          api_data = {}
          Wxpay.logger.debug("resp_is #{resp_xml.to_s}")
          resp_xml.xpath("//xml").children.each {|a|
            api_data[a.name] = a.content if a.content.present?
          }
          api_data
      end

      def self.generate_signature(fields)
        Wxpay.logger.debug("fields are #{fields.inspect}")
        Wxpay.logger.debug("signed_string are #{signed_string(fields)}")

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

      def self.auth_client
        @@auth_client ||= WeixinAuthorize::Client.new(@@credentials[:appid], @@appsecret) rescue nil
      end

      module Common
        def self.included(klass)
          fields = []
          fields += klass::REQUIRED_FIELDS_BIZ_SUCCESS if klass.const_defined?(:REQUIRED_FIELDS_BIZ_SUCCESS)
          fields += klass::OPTIONAL_FIELDS_BIZ_SUCCESS if klass.const_defined?(:OPTIONAL_FIELDS_BIZ_SUCCESS)

          fields.each do |param|
            case 
            when MONEY_FIELDS.include?(param)  
              klass.class_eval <<-EOF
               def #{param}
                 Money.new(params['#{param}'].to_i, currency)
               end
             EOF
            when TIME_FIELDS.include?(param)
              klass.class_eval <<-EOF
                def #{param}
                  Time.parse params['#{param}']
                end
              EOF
            else
              klass.class_eval <<-EOF
                def #{param}
                  params['#{param}']
                end
                EOF
            end
          end
        end

        def has_all_required_fields?
          (!self.class.const_defined?(:REQUIRED_FIELDS) ||
            self.class::REQUIRED_FIELDS.all? {|f| params[f].present?})
          .tap {|r| Wxpay.logger.debug("#{self.class.name} requiring #{self.class::REQUIRED_FIELDS} but getting #{params}") unless r }
        end

        def params
          @params ||= @fields
        end

        def verify_signature
          #puts "generated #{Wxpay.generate_signature(@params)}"
          (@params["sign"] == Wxpay.generate_signature(@params))
          .tap {|r| Wxpay.logger.debug("#{__LINE__}: Got signature #{@params["sign"]} while expecting #{Wxpay.generate_signature(@params)}.") unless r }
        end

        def acknowledge
          verify_signature || raise(ActionViewHelperError, "Invalid Wxpay HTTP signature")
        end

        def to_xml(options = {})
          Wxpay.logger.debug("#{__FILE__}:#{__LINE__}: options is #{options.inspect}")
          Nokogiri::XML::Builder.new do |x|
            x.xml {
              (form_fields rescue params).each {|k,v|
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
            msg = "Requiring #{self.class::REQUIRED_FIELDS.sort.to_s} \n Getting #{Wxpay.credentials.merge(biz_data).keys.map(&:to_s).sort.to_s}"
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
          #puts "#{@response.inspect}"
          raise CommunicationError, @response.return_code unless @response.comm_success?
          raise CredentialMismatchError unless @response.credentials_match?(params)
          raise UnVerifiableResponseError  unless @response.acknowledge
          @response #let somebody upstream handle the biz logic
        end
      end

      class GetBrandWCPayHelper < ::OffsitePayments::Helper
        include Wxpay::Common
        REQUIRED_FIELDS = %w(package) 
        API_REQUEST = :get_brand_wcpay
        def initialize(prepay_id)
          @fields = {}
          @fields['appId']    = Wxpay.credentials[:appid]
          @fields['package']  = "prepay_id=#{prepay_id}"
          @fields['signType'] = 'MD5'
        end

        def sign
          @fields['timeStamp'] = Time.now().to_i.to_s
          @fields['nonceStr']  = SecureRandom.hex
          add_field('paySign', Wxpay.generate_signature(@fields))
        end

        def payload
          @fields['paySign'] || sign
          @fields
        end
      end

      # These helper need to inherit from OffsitePayments::Helper therefore has to have CommomHelper mixed in
      class UnifiedOrderHelper < ::OffsitePayments::Helper 
        include Wxpay::Common
        include Wxpay::CommonHelper
        include ActiveMerchant::PostsData
        REQUIRED_FIELDS = %w(body out_trade_no total_fee spbill_create_ip notify_url trade_type) 
        API_REQUEST = :unifiedorder
        def initialize(data )
          load_data(data)
        end
      end

      class OrderQueryHelper < ::OffsitePayments::Helper
        REQUIRED_FIELDS = %w(out_trade_no) 
        API_REQUEST = :orderquery
        include Wxpay::Common
        include Wxpay::CommonHelper
        include ActiveMerchant::PostsData
        def initialize(data)
          load_data(data)
        end
      end
      
      class ShortUrlHelper < ::OffsitePayments::Helper
        REQUIRED_FIELDS = %w(long_url) 
        API_REQUEST = :shorturl
        include Wxpay::Common
        include Wxpay::CommonHelper
        include ActiveMerchant::PostsData
        def initialize(data)
          load_data(data)
        end
      end

      class BaseResponse
        REQUIRED_FIELDS = %w(return_code)
        REQUIRED_RETURN_CREDENTIAILS = %w(appid mch_id)
        #include Wxpay::Common
        require 'nokogiri'
        attr_reader :params

        def initialize(data, options = {})
          raise "#{data}" unless (data.is_a? Hash)
          @params = data
          raise "Not valid #{self.class.name} \n data is #{data} params is #{params}" unless has_all_required_fields?
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
        REQUIRED_FIELDS_BIZ_SUCCESS = %w(openid is_subscribe trade_type bank_type total_fee transaction_id out_trade_no time_end)
        OPTIONAL_FIELDS_BIZ_SUCCESS = %w(coupon_fee fee_type attach return_msg cash_fee)
        include Wxpay::Common
        alias_method :success?, :biz_success?
        alias_method :amount, :total_fee
        alias_method :currency, :fee_type
        def api_response( response )
          data = {}
          case response
          when :success
            data['return_code'] = 'SUCCESS'
          else
            data['return_code'] = 'FAIL'
            data['return_msg'] = response.to_s
          end
          ApiResponse::NotificationResponse.new(data)
        end
      end

      module ApiResponse
        module Common
          def biz_payload
            params.select {|k,v| 
              (self.class::REQUIRED_FIELDS_BIZ_SUCCESS.include?(k) if self.class.const_defined?(:REQUIRED_FIELDS_BIZ_SUCCESS)) ||
                (self.class::OPTIONAL_FIELDS_BIZ_SUCCESS.include?(k) if self.class.const_defined?(:OPTIONAL_FIELDS_BIZ_SUCCESS))
            }
          end

        end

        def self.parse_response(api_request, http_response)
          api_data = Wxpay.parse_xml(http_response)
          case api_request
          when :unifiedorder; UnifiedOrderResponse.new(api_data);
          when :orderquery; OrderQueryResponse.new(api_data);
          when :shorturl; ShortUrlResponse.new(api_data);
          else raise "UnSupported Wxpay API request #{api_request.to_s}";
          end
        end

        class NotificationResponse < BaseResponse
          #  REQUIRED_FIELDS_BIZ_SUCCESS = %w(return_code)
          OPTIONAL_FIELDS_BIZ_SUCCESS = %w(return_msg)
          include Wxpay::Common
          include ApiResponse::Common
        end

        class UnifiedOrderResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(trade_type prepay_id)
          OPTIONAL_FIELDS_BIZ_SUCCESS = %w(code_url)
          include Wxpay::Common
          include ApiResponse::Common
          alias_method :pay_url, :code_url
        end

        class OrderQueryResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(trade_state openid is_subscribe trade_type bank_type total_fee time_end)
          OPTIONAL_FIELDS_BIZ_SUCCESS = %w(device_info coupone_fee fee_type transaction_id out_trade_no attach)
          include Wxpay::Common
          include ApiResponse::Common
          alias_method :amount, :total_fee
          alias_method :currency, :fee_type
        end

        class ShortUrlResponse < BaseResponse
          REQUIRED_FIELDS_BIZ_SUCCESS = %w(short_url)
          OPTIONAL_FIELDS_BIZ_SUCCESS = []
          include Wxpay::Common
          include ApiResponse::Common
        end
      end

    end
end
end
