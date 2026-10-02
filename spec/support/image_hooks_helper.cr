# Test seams for ImageHooks' class-level maps, which a build fills only
# through the `image:resize` hook.
class Hwaro::Content::Hooks::ImageHooks
  def self.resize_map : Hash(String, Hash(Int32, String))
    @@resize_map_mutex.synchronize { @@resize_map.dup }
  end

  def self.set_resize_map(map : Hash(String, Hash(Int32, String)))
    @@resize_map_mutex.synchronize { @@resize_map = map }
  end

  def self.lqip_map : Hash(String, Hash(String, String))
    @@lqip_map_mutex.synchronize { @@lqip_map.dup }
  end

  def self.set_lqip_map(map : Hash(String, Hash(String, String)))
    @@lqip_map_mutex.synchronize { @@lqip_map = map }
  end
end
