# encoding: utf-8
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module AlipayWap

      mattr_accessor :service_url, :logger, :credentials
      @@service_url = 'http://wappaygw.alipay.com/service/rest.htm'
        #SERVICE_URL = 
      FIELDS_NOT_TO_BE_SIGNED = %w(sign sign_type)

      def self.credentials=(cred)
        @@credentials = cred
      end

      def self.logger
        @@logger ||= Logger.new(STDOUT)
      end

      ##########################################################################################################################
      # Below is the WAP stuff
      ##########################################################################################################################
      module WapCommon
      end

      module CredentialHelper
      end

      module SignHelper
        FIELDS_NOT_TO_BE_SIGNED = 'sign'

        def key
          AlipayWap.credentials[:key]
        end

        def sign
          @fields['sign'] ||= generate_signature
        end

        def generate_signature
          case sign_type = @fields["sec_id"]
          when 'MD5'
            Digest::MD5.hexdigest(signed_string)
          when '0001' #RSA
            raise OffsitePayments::ActionViewHelperError, "sign_type '0001' -> RSA not yet supported"
          when nil
            raise OffsitePayments::ActionViewHelperError, "'sign_type' must be specified in the fields"
          else
            raise OffsitePayments::ActionViewHelperError, "sign_type '#{sign_type}' not yet supported"
          end
        end

        # Generate the string to sign on from the fields. 
        # Currently Alipay doc specifies that the fields are arranged alphabetically except for data sent to "notify_url"
        def signed_string(sort_first = true)
          signed_data_only = @fields.reject { |s| FIELDS_NOT_TO_BE_SIGNED.include?(s) }
          ( sort_first ? signed_data_only.sort : signed_data_only )
          .collect { |s| s[0]+"="+CGI.unescape(s[1]) }
          .join("&") + key
        end

        def acknowledge
         ( @fields["sign"] == generate_signature ) || raise(SecurityError, "Invalid Alipay HTTP signature in #{self.class}")
        end
      end

      module OutgoingRequestHelper
        def process
          @post_response = ssl_post(SERVICE_URL, payload)
          @response = parse_response #(self.class::API_REQUEST, post_response)
        end

        def parse_response
          case self.class
          when CreateDirectHelper
            CreateDirectResponse.new(@post_response, self)
          else
            raise "response class for #{self.class.name} not defined/implemented yet"
          end
        end

      end
      class CreateDirectHelper < OffsitePayments::Helper
        include WapCommon
        include SignHelper
        include OutgoingRequestHelper

        def initialize(biz_data)
          @biz_data = biz_data.merge(seller_account_name: AlipayWap.credentials[:seller][:email])
          @fields = {
            'partner' => AlipayWap.credentials[:pid].to_s,
            'service' => 'alipay.wap.trade.create.direct',
            'format'  => 'xml',
            'v'       => '2.0',
            'sec_id'  => 'MD5',
            'req_id'  => SecureRandom.hex(16).to_s,
            'req_data' => payload_xml(@biz_data),
          }
          sign
        end

        def payload

        end

        def payload_xml(biz_data)
          xml = biz_data.map {|k, v| "<#{k}>#{v.encode(:xml => :text)}</#{k}>" }.join
          "<direct_trade_create_req>#{xml}</direct_trade_create_req>"
        end

      end

      class CreateDirectResponse
        require 'nokogiri'
        include SignHelper
        attr_reader :request_token, :error
        # ignore_signature_check should be used in testing only!
        def initialize(raw_response, req, ignore_signature_check = false)
          @raw_response, @request = raw_response, req
          parse ignore_signature_check
        end

        def parse(ignore_signature_check)
          raise TypeError unless @raw_response.is_a? String
          @fields = @raw_response.split('&').inject({}) {|h, kv| k,v = kv.split('=',2); h[k] = v; h}
          credential_check

          case
          when @fields.has_key?('res_data')
            acknowledge unless ignore_signature_check
            @request_token = Nokogiri::XML(@fields['res_data']).at_xpath("//request_token").content
          when @fields.has_key?('res_error')
            @error = Nokogiri::XML(@fields['res_error']).xpath('//err').children.inject({}) {|h,node|
              h[node.name] = node.content.strip; h
            }
          else
            raise "Invalid response format for #{self.class}"
          end
        end

        # verify if this response is for this request
        def credential_check
          %w(partner req_id service v).all? {|k| @fields[k] == @request.form_fields[k].to_s } || raise("Response is not right")
        end
      end

      class AuthAndExecuteHelper < OffsitePayments::Helper
        include WapCommon
        include SignHelper
      end

    end#
end
end
