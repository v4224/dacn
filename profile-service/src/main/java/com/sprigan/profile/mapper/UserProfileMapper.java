package com.sprigan.profile.mapper;

import org.mapstruct.Mapper;

import com.sprigan.profile.dto.request.ProfileCreationRequest;
import com.sprigan.profile.dto.response.UserProfileResponse;
import com.sprigan.profile.entity.UserProfile;

@Mapper(componentModel = "spring")
public interface UserProfileMapper {
    UserProfile toUserProfile(ProfileCreationRequest request);

    UserProfileResponse toUserProfileReponse(UserProfile entity);
}
