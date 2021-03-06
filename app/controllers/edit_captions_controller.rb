require 'fileutils'
require 'jwt'

class EditCaptionsController < ApplicationController

    def download_vtt
      record_id = params[:record_id]
      token = params[:token]
      props = YAML.load_file('credentials.yaml')      
      tts_shared_secret = props['tts_shared_secret']
      decoded_token = JWT.decode token, tts_shared_secret, true, {algorithm: 'HS256'}

      bbb_checksum = decoded_token[0]['bbb_checksum']
      bbb_url = decoded_token[0]['bbb_url']

      props = YAML.load_file('settings.yaml')
      storage_dir = props['storage_dir']
      recording_dir = "#{storage_dir}/#{record_id}"

      req = "#{bbb_url}/bigbluebutton/api/getRecordingTextTracks?recordID=#{record_id}&checksum=#{bbb_checksum}"
      response = HTTParty.get(req)
      res = JSON.load(response.body)
      url = res["response"]["tracks"][0]["href"]
      if url.nil?
        render json: {"message": "no url found as a response from BBB"}
        return
      else
        unless Dir.exist?(recording_dir)
          system("mkdir #{recording_dir}")
        end
        open("#{recording_dir}/captions_en-US.vtt", 'wb') do |file|
          file << open(url).read
        end
      end

      current_time = (Time.now.to_f * 1000).to_i
      vtt_file = "#{recording_dir}/captions_en-US.vtt"
      if File.exist?(vtt_file)
          File.open(vtt_file, 'r') do |f|
            send_data f.read, type: "application/vtt"
          end
          File.delete(vtt_file)
      else
        puts "*** VTT file ===> not found ***"
        data = "{\"message\" : \"vtt file not found\"}"
        render :json=>data
        return
      end

      if Dir.exist?(recording_dir)
        FileUtils.rm_rf(recording_dir)
      end
    end

    def download_audio
      record_id = params[:record_id]
      token = params[:token]
      props = YAML.load_file('credentials.yaml')      
      tts_shared_secret = props['tts_shared_secret']
      decoded_token = JWT.decode token, tts_shared_secret, true, {algorithm: 'HS256'}

      bbb_checksum = decoded_token[0]['bbb_checksum']
      bbb_url = decoded_token[0]['bbb_url']
            
      props = YAML.load_file('settings.yaml')
      storage_dir = props['storage_dir']
      recording_dir = "#{storage_dir}/#{record_id}"

      req = "#{bbb_url}/bigbluebutton/api/getRecordings?recordID=#{record_id}&checksum=#{bbb_checksum}"
      response = HTTParty.get(req)
      doc = Nokogiri::XML(response.body)

      audio_url = doc.root.xpath("recordings/recording/playback/format/url").first.text

      unless Dir.exist?(recording_dir)
        system("mkdir #{recording_dir}")
      end

      open("#{recording_dir}/audio.wav", 'wb') do |file|
          file << open(audio_url).read
      end

      File.open("#{recording_dir}/audio.wav", 'r') do |f|
        send_data f.read, type: "audio/wav"
      end
      File.delete("#{recording_dir}/audio.wav")

      if Dir.exist?(recording_dir)
        FileUtils.rm_rf(recording_dir)
      end
    end

    def upload_vtt

      vtt_file = params['file']
      record_id = params[:record_id]
      token = params[:token]
      props = YAML.load_file('credentials.yaml')      
      tts_shared_secret = props['tts_shared_secret']
      decoded_token = JWT.decode token, tts_shared_secret, true, {algorithm: 'HS256'}

      bbb_checksum = decoded_token[0]['bbb_checksum']
      bbb_url = decoded_token[0]['bbb_url']
      kind = decoded_token[0]['kind']
      label = decoded_token[0]['label']
      caption_locale = decoded_token[0]['caption_locale']

      if vtt_file.nil?
        data = "{\"message\" : \"missing param file\"}"
        render :json=>data
        return
      end

      props = YAML.load_file('settings.yaml')
      storage_dir = props['storage_dir']
      recording_dir = "#{storage_dir}/#{record_id}"
      current_time = (Time.now.to_f * 1000).to_i

      if(delete_files(recording_dir))
        File.open("#{recording_dir}/#{record_id}-#{current_time}-track.vtt", 'w') do |file|
          file.write vtt_file.read
        end

        data = {
          'record_id' => record_id.to_s,
          'storage_dir' => recording_dir,
          'current_time' => current_time,
          'caption_locale' => caption_locale,
          'bbb_url' => bbb_url,
          'bbb_checksum' => bbb_checksum,
          'kind' => kind,
          'label' => label
        }

        $redis.lpush('caption_editing_job', data.to_json)

      end
    end

    private
    def delete_files(recording_dir)
      if Dir.exist?(recording_dir)
        vtt_files = Dir["#{recording_dir}/*.vtt"]
      else
        data = "{\"message\" : \"record_id not found\"}"
        render :json=>data
        return false
      end

      unless vtt_files[0].nil?
        system("rm #{vtt_files[0]}")
      end
      return true
    end

end
