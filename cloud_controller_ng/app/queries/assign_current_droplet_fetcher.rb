module VCAP::CloudController
  class AssignCurrentDropletFetcher
    def fetch(app_guid, droplet_guid)
      app = AppModel.where(guid: app_guid).eager(:processes, :space, :droplets, space: :organization).all.first
      return nil if app.nil?

      org = app.space ? app.space.organization : nil
      droplet = app.droplets.detect { |d| d.guid == droplet_guid }#从app的droplet中找到当前的droplet
      [app, app.space, org, droplet]
    end
  end
end
