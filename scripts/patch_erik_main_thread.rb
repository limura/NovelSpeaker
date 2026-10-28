# Apply the reviewable vendor diff used by patch.sh, without interactive/reverse guesses.
require 'digest'
require 'open3'
require 'tempfile'
require 'tmpdir'

module NovelSpeakerErikMainThreadPatch
  ORIGINAL_SHA256 = 'ff683283353fac1fb51dc1ec627d1905529b3c96a9c1e07a89ed973514cbe9b1'.freeze
  PATCHED_SHA256 = 'c6ca6b2f67a471c731f71eae10f93686a71e554fbe47973bb3fce4f523523f05'.freeze
  DEFAULT_PATCH = File.expand_path('../Erik_LayoutEngine.swift.patch', __dir__).freeze

  def self.apply(path, patch_path = DEFAULT_PATCH)
    raise 'Missing Erik patch file' unless File.file?(patch_path)
    source = File.binread(path)
    fingerprint = Digest::SHA256.hexdigest(source)
    return :already_patched if fingerprint == PATCHED_SHA256
    raise 'Unrecognized Erik source; review Erik_LayoutEngine.swift.patch before applying' unless fingerprint == ORIGINAL_SHA256
    permissions = File.stat(path).mode & 0777
    Dir.mktmpdir('novelspeaker-erik-patch-') do |directory|
      candidate = File.join(directory, 'LayoutEngine.swift')
      File.binwrite(candidate, source)
      _, status = Open3.capture2e('/usr/bin/patch', '--batch', '--forward', '-F', '0', candidate, File.expand_path(patch_path))
      raise 'Erik patch does not apply cleanly; original file unchanged' unless status.success?
      result = File.binread(candidate)
      raise 'Unexpected Erik patch result; original file unchanged' unless Digest::SHA256.hexdigest(result) == PATCHED_SHA256
      # Publish only a fully validated copy, retaining CocoaPods source permissions.
      Tempfile.create(['.Erik-LayoutEngine-', '.swift'], File.dirname(path)) do |temporary|
        temporary.binmode
        temporary.write(result)
        temporary.flush
        File.chmod(permissions, temporary.path)
        File.rename(temporary.path, path)
      end
    end
    :patched
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.fetch(0) { File.expand_path('../Pods/Erik/Sources/LayoutEngine.swift', __dir__) }
  patch_path = ARGV.fetch(1) { NovelSpeakerErikMainThreadPatch::DEFAULT_PATCH }
  puts NovelSpeakerErikMainThreadPatch.apply(path, patch_path)
end
