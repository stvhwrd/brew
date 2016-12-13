require "test_helper"

describe Hbc::Artifact::Uninstall do
  let(:cask) { Hbc.load("with-installable") }

  let(:uninstall_artifact) {
    Hbc::Artifact::Uninstall.new(cask, command: Hbc::FakeSystemCommand)
  }

  before do
    shutup do
      TestHelper.install_without_artifacts(cask)
    end
  end

  describe "install_phase" do
    it "does nothing, because the install_phase method is a no-op" do
      shutup do
        uninstall_artifact.install_phase
      end
    end
  end

  describe "zap_phase" do
    it "does nothing, because the zap_phase method is a no-op" do
      shutup do
        uninstall_artifact.zap_phase
      end
    end
  end

  describe "uninstall_phase" do
    subject do
      shutup do
        uninstall_artifact.uninstall_phase
      end
    end

    describe "when using launchctl" do
      let(:cask) { Hbc.load("with-uninstall-launchctl") }
      let(:launchctl_list_cmd) { %w[/bin/launchctl list my.fancy.package.service] }
      let(:launchctl_remove_cmd) { %w[/bin/launchctl remove my.fancy.package.service] }
      let(:unknown_response) { "launchctl list returned unknown response\n" }
      let(:service_info) {
        <<-EOS.undent
          {
                  "LimitLoadToSessionType" = "Aqua";
                  "Label" = "my.fancy.package.service";
                  "TimeOut" = 30;
                  "OnDemand" = true;
                  "LastExitStatus" = 0;
                  "ProgramArguments" = (
                          "argument";
                  );
          };
        EOS
      }

      describe "when launchctl job is owned by user" do
        it "can uninstall" do
          Hbc::FakeSystemCommand.stubs_command(
            launchctl_list_cmd,
            service_info
          )

          Hbc::FakeSystemCommand.stubs_command(
            sudo(launchctl_list_cmd),
            unknown_response
          )

          Hbc::FakeSystemCommand.expects_command(launchctl_remove_cmd)

          subject
        end
      end

      describe "when launchctl job is owned by system" do
        it "can uninstall" do
          Hbc::FakeSystemCommand.stubs_command(
            launchctl_list_cmd,
            unknown_response
          )

          Hbc::FakeSystemCommand.stubs_command(
            sudo(launchctl_list_cmd),
            service_info
          )

          Hbc::FakeSystemCommand.expects_command(sudo(launchctl_remove_cmd))

          subject
        end
      end
    end

    describe "when using pkgutil" do
      let(:cask) { Hbc.load("with-uninstall-pkgutil") }
      let(:main_pkg_id) { "my.fancy.package.main" }
      let(:agent_pkg_id) { "my.fancy.package.agent" }
      let(:main_files) {
        %w[
          fancy/bin/fancy.exe
          fancy/var/fancy.data
        ]
      }
      let(:main_dirs) {
        %w[
          fancy
          fancy/bin
          fancy/var
        ]
      }
      let(:agent_files) {
        %w[
          fancy/agent/fancy-agent.exe
          fancy/agent/fancy-agent.pid
          fancy/agent/fancy-agent.log
        ]
      }
      let(:agent_dirs) {
        %w[
          fancy
          fancy/agent
        ]
      }
      let(:pkg_info_plist) {
        <<-EOS.undent
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
                  <key>install-location</key>
                  <string>tmp</string>
                  <key>volume</key>
                  <string>/</string>
          </dict>
          </plist>
        EOS
      }

      it "can uninstall" do
        Hbc::FakeSystemCommand.stubs_command(
          %w[/usr/sbin/pkgutil --pkgs=my.fancy.package.*],
          "#{main_pkg_id}\n#{agent_pkg_id}"
        )

        [
          [main_pkg_id, main_files, main_dirs],
          [agent_pkg_id, agent_files, agent_dirs],
        ].each do |pkg_id, pkg_files, pkg_dirs|
          Hbc::FakeSystemCommand.stubs_command(
            %W[/usr/sbin/pkgutil --only-files --files #{pkg_id}],
            pkg_files.join("\n")
          )

          Hbc::FakeSystemCommand.stubs_command(
            %W[/usr/sbin/pkgutil --only-dirs --files #{pkg_id}],
            pkg_dirs.join("\n")
          )

          Hbc::FakeSystemCommand.stubs_command(
            %W[/usr/sbin/pkgutil --files #{pkg_id}],
            (pkg_files + pkg_dirs).join("\n")
          )

          Hbc::FakeSystemCommand.stubs_command(
            %W[/usr/sbin/pkgutil --pkg-info-plist #{pkg_id}],
            pkg_info_plist
          )

          Hbc::FakeSystemCommand.expects_command(sudo(%W[/usr/sbin/pkgutil --forget #{pkg_id}]))

          Hbc::FakeSystemCommand.expects_command(
            sudo(%w[/bin/rm -f --] + pkg_files.map { |path| Pathname("/tmp/#{path}") })
          )
        end

        subject
      end
    end

    describe "when using kext" do
      let(:cask) { Hbc.load("with-uninstall-kext") }
      let(:kext_id) { "my.fancy.package.kernelextension" }

      it "can uninstall" do
        Hbc::FakeSystemCommand.stubs_command(
          sudo(%W[/usr/sbin/kextstat -l -b #{kext_id}]), "loaded"
        )

        Hbc::FakeSystemCommand.expects_command(
          sudo(%W[/sbin/kextunload -b #{kext_id}])
        )

        Hbc::FakeSystemCommand.expects_command(
          sudo(%W[/usr/sbin/kextfind -b #{kext_id}]), "/Library/Extensions/FancyPackage.kext\n"
        )

        Hbc::FakeSystemCommand.expects_command(
          sudo(["/bin/rm", "-rf", "/Library/Extensions/FancyPackage.kext"])
        )

        subject
      end
    end

    describe "when using quit" do
      let(:cask) { Hbc.load("with-uninstall-quit") }
      let(:bundle_id) { "my.fancy.package.app" }
      let(:count_processes_script) {
        'tell application "System Events" to count processes ' +
          %Q(whose bundle identifier is "#{bundle_id}")
      }
      let(:quit_application_script) {
        %Q(tell application id "#{bundle_id}" to quit)
      }

      it "can uninstall" do
        Hbc::FakeSystemCommand.stubs_command(
          sudo(%W[/usr/bin/osascript -e #{count_processes_script}]), "1"
        )

        Hbc::FakeSystemCommand.stubs_command(
          sudo(%W[/usr/bin/osascript -e #{quit_application_script}])
        )

        subject
      end
    end

    describe "when using signal" do
      let(:cask) { Hbc.load("with-uninstall-signal") }
      let(:bundle_id) { "my.fancy.package.app" }
      let(:signals) { %w[TERM KILL] }
      let(:unix_pids) { [12_345, 67_890] }
      let(:get_unix_pids_script) {
        'tell application "System Events" to get the unix id of every process ' +
          %Q(whose bundle identifier is "#{bundle_id}")
      }

      it "can uninstall" do
        Hbc::FakeSystemCommand.stubs_command(
          sudo(%W[/usr/bin/osascript -e #{get_unix_pids_script}]), unix_pids.join(", ")
        )

        signals.each do |signal|
          Process.expects(:kill).with(signal, *unix_pids)
        end

        subject
      end
    end

    describe "when using delete" do
      let(:cask) { Hbc.load("with-uninstall-delete") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(
          sudo(%w[/bin/rm -rf --],
               Pathname.new("/permissible/absolute/path"),
               Pathname.new("~/permissible/path/with/tilde").expand_path)
        )

        subject
      end
    end

    describe "when using trash" do
      let(:cask) { Hbc.load("with-uninstall-trash") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(
          sudo(%w[/bin/rm -rf --],
               Pathname.new("/permissible/absolute/path"),
               Pathname.new("~/permissible/path/with/tilde").expand_path)
        )

        subject
      end
    end

    describe "when using rmdir" do
      let(:cask) { Hbc.load("with-uninstall-rmdir") }
      let(:dir_pathname) { Pathname.new("#{TEST_FIXTURE_DIR}/cask/empty_directory") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(
          sudo(%w[/bin/rm -f --], dir_pathname.join(".DS_Store"))
        )

        Hbc::FakeSystemCommand.expects_command(
          sudo(%w[/bin/rmdir --], dir_pathname)
        )

        subject
      end
    end

    describe "when using script" do
      let(:cask) { Hbc.load("with-uninstall-script") }
      let(:script_pathname) { cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(%w[/bin/chmod -- +x] + [script_pathname])

        Hbc::FakeSystemCommand.expects_command(
          sudo(cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool"), "--please")
        )

        subject
      end
    end

    describe "when using early_script" do
      let(:cask) { Hbc.load("with-uninstall-early-script") }
      let(:script_pathname) { cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(%w[/bin/chmod -- +x] + [script_pathname])

        Hbc::FakeSystemCommand.expects_command(
          sudo(cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool"), "--please")
        )

        subject
      end
    end

    describe "when using login_item" do
      let(:cask) { Hbc.load("with-uninstall-login-item") }

      it "can uninstall" do
        Hbc::FakeSystemCommand.expects_command(
          ["/usr/bin/osascript", "-e", 'tell application "System Events" to delete every login ' \
                                       'item whose name is "Fancy"']
        )

        subject
      end
    end
  end
end