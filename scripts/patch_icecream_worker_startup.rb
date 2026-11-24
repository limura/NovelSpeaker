# Apply the local queue fix and serialize first worker creation for IceCream 2.0.4.
require 'digest'
require 'tempfile'

module NovelSpeakerIceCreamWorkerStartupPatch
  VERSION = '2.0.4'.freeze
  # CocoaPods pristine source and the previous app queue-only patch, respectively.
  INPUT_SHA256 = %w[
    ad480eb9492df01007d6044aa69009def94973d1ed1de4160b655aa591da29f4
    7f5d7f182d579900d79ed18cbec6bd3417524d7d7a08fc5d2a168f9260c920c1
  ].freeze
  OUTPUT_SHA256 = 'aef8c9951539c0fcb1eb1a96d72ba892d8ee0e52dba285d40d9406f02b849fa0'.freeze
  REPLACEMENT = File.join(__dir__, 'IceCream_2_0_4_BackgroundWorker.swift').freeze
  WORKER = 'IceCream/Classes/BackgroundWorker.swift'.freeze

  def self.apply(path, version)
    unless version.to_s == VERSION
      raise "IceCream #{version.inspect} is not audited for the worker startup fix (expected #{VERSION})"
    end

    source_hash = Digest::SHA256.file(path).hexdigest
    return :already_patched if source_hash == OUTPUT_SHA256
    unless INPUT_SHA256.include?(source_hash)
      raise 'Unrecognized IceCream BackgroundWorker.swift; refusing to replace it'
    end

    result = File.binread(REPLACEMENT)
    unless Digest::SHA256.hexdigest(result) == OUTPUT_SHA256
      raise 'IceCream worker replacement fingerprint mismatch; original unchanged'
    end

    path = path.to_s
    permissions = File.stat(path).mode & 0777
    Tempfile.create(['.IceCream-BackgroundWorker-', '.swift'], File.dirname(path)) do |temporary|
      temporary.binmode
      temporary.write(result)
      temporary.flush
      File.chmod(permissions, temporary.path)
      File.rename(temporary.path, path)
    end
    :patched
  end

  def self.install(installer)
    versions = installer.pod_targets.map(&:root_spec).select { |spec| spec.name == 'IceCream' }
                        .map { |spec| spec.version.to_s }.uniq
    unless versions == [VERSION]
      raise "Expected resolved IceCream #{VERSION}; got #{versions.inspect}"
    end

    apply(installer.sandbox.pod_dir('IceCream').join(WORKER), versions.first)
  end
end

if $PROGRAM_NAME == __FILE__
  pods = File.expand_path('../Pods', __dir__)
  versions = File.read(File.join(pods, 'Manifest.lock')).scan(/^  - IceCream \(([^)]+)\):?$/).flatten
  unless versions == [NovelSpeakerIceCreamWorkerStartupPatch::VERSION]
    abort "Unrecognized installed IceCream version: #{versions.inspect}"
  end
  puts NovelSpeakerIceCreamWorkerStartupPatch.apply(
    File.join(pods, 'IceCream', NovelSpeakerIceCreamWorkerStartupPatch::WORKER), versions.first
  )
end
