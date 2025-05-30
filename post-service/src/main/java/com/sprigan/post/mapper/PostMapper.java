package com.sprigan.post.mapper;

import com.sprigan.post.dto.response.PostResponse;
import com.sprigan.post.entity.Post;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface PostMapper {
    PostResponse toPostResponse(Post post);
}
