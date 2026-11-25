# Refuse unknown IceCream source before patching any installed files.
require 'digest'
require 'fileutils'
require 'open3'
require 'pathname'
require 'tempfile'
require 'tmpdir'

module NovelSpeakerIceCreamPrivateReceiveACK
  VERSION = '2.0.4'.freeze
  PATCH = File.join(__dir__, 'IceCream_2_0_4_PrivateReceiveACK.patch').freeze
  PATCH_SHA256 = '007282a0622a086eb20b7ac3f4565da86dca3748b3679dc9c0183e25ee142c26'.freeze
  FILES = <<~HASHES.lines.map(&:split).freeze
    CKRecordConvertible.swift f9198a0a7733b40a6e1c599413b9be039a97c5dc04c824ea107182797577ad50 c3d9a132f467459499b2541b2b8a50acece6aee65552586ce3ac85f3a53c106f
    CKRecordRecoverable.swift e22de551c3d538e7062aa7af6a65359c853bd3d83038b2561a653467b67a2366 580eee6fb88a09371fe760e2889d835cae19aabcd6dc600959bb1a91102fa389
    CreamAsset.swift 0e496bc2707d54e3c1e3d584b6071ce7fc3c82a052fca724fd9f0a472b5b3a08 4180594974fbf883e7888f069f4dfa8aa65dcc98e9b7ed4e38f88135338e082c
    PrivateDatabaseManager.swift b6bd664fca7e134139a5691cb977c736942d6f2fa80233634ccad85b87b69196 2a1e47d8de9cc26f72038a146b8934a40cb72bb12261baf0b3103df3713ddd71
    SyncEngine.swift f01f074f29c751ae97a4df187babf740d808294917ba3a73fe2e449d3a147caa a9d815e218a5eba415ffd247f60d58b47d733f7f59ae17a69616f166a6d90b33
    SyncObject.swift 3814a0a1cac514799651275cda6ec947d021c78c12698bdbb97b6a1fd70bbb9c 466758f7b62f57153b91fd54aa604727316e1180365dd5120ccd473bb2f6cd02
    Syncable.swift fd7514e12fb32d16bd34c274c30bca860ed32e40dbb5f709483a6d549e3b10f2 f5645a59d64e0036a6b9c3bb1c094911dabd4acea5b7025658be44aca9ce4af1
  HASHES

  # patch.sh also carries the historical non-ASCII assertion adjustment.
  # Its source and fully patched result are audited alongside pristine Pods.
  CONVERTIBLE_STOCK = %w[6bbefd39707c42b5412ac7eb7c1443a7f3fa27b8d50e1f63cbbcc40da6e486b1 dc5a6366413ebf00ec3a8b896b8a02fdabfc35ada386dc9c6be42943be84edae].freeze

  def self.apply(directory, version)
    raise "IceCream #{version.inspect} not audited" unless version.to_s == VERSION
    raise 'Unrecognized receive ACK patch' unless Digest::SHA256.file(PATCH).hexdigest == PATCH_SHA256
    root = Pathname.new(directory).expand_path
    relative = 'IceCream/Classes'
    files = FILES.map do |name, before, after|
      installed = root.join(relative, name)
      hash = Digest::SHA256.file(installed).hexdigest
      if name == 'CKRecordConvertible.swift' && CONVERTIBLE_STOCK.include?(hash)
        before, after = CONVERTIBLE_STOCK
      end
      raise "Unrecognized IceCream #{name}; original unchanged" unless [before, after].include?(hash)
      [name, after, hash == after]
    end
    return :already_patched if files.all?(&:last)
    # Verify/recover a mixed install using reproducible input data from the
    # installed copies themselves. Apply the known diff independently per file
    # in scratch, never directly to a user/dependency file before verification.
    Dir.mktmpdir('.icecream-receive-ack-', root) do |tmp|
      staged = Pathname.new(tmp).join(relative)
      staged.mkpath
      files.each do |name, after, already_patched|
        installed = root.join(relative, name)
        fs = staged.join(name)
        next if already_patched
        FileUtils.cp(installed, fs)
        File.chmod(0o644, fs)
        stdout, stderr, status = Open3.capture3('/usr/bin/patch','-f','-s',fs.to_s, stdin_data: file_patch(name))
        raise "IceCream patch failed (#{name}): #{stdout} #{stderr}" unless status.success?
        raise "IceCream patch fingerprint mismatch (#{name})" unless Digest::SHA256.file(fs).hexdigest == after
        File.chmod(File.stat(installed).mode & 0o777, fs)
      end
      files.each do |name, _after, already_patched|
        next if already_patched
        File.rename(staged.join(name), root.join(relative,name))
      end
    end
    :patched
  end

  def self.file_patch(name)
    text = File.binread(PATCH)
    blocks = text.split(/(?=^--- IceCream\/Classes\/)/m)
    blocks.find { |block| block.start_with?("--- IceCream/Classes/#{name}\n") } || raise("Missing IceCream patch for #{name}")
  end

  def self.install(installer)
    versions = installer.pod_targets.map(&:root_spec).select { |spec| spec.name == 'IceCream' }.map { |spec| spec.version.to_s }.uniq
    raise "Expected IceCream #{VERSION}; got #{versions.inspect}" unless versions == [VERSION]
    apply(installer.sandbox.pod_dir('IceCream'), versions.first)
  end
end

if $PROGRAM_NAME == __FILE__
  pods = File.expand_path('../Pods', __dir__)
  versions = File.read(File.join(pods,'Manifest.lock')).scan(/^  - IceCream \(([^)]+)\):?$/).flatten
  abort "Unrecognized installed IceCream version: #{versions.inspect}" unless versions == [NovelSpeakerIceCreamPrivateReceiveACK::VERSION]
  puts NovelSpeakerIceCreamPrivateReceiveACK.apply(File.join(pods,'IceCream'),versions.first)
end
