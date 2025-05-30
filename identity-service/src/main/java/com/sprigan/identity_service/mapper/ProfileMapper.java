package com.sprigan.identity_service.mapper;

import org.mapstruct.Mapper;

import com.sprigan.identity_service.dto.request.ProfileCreationRequest;
import com.sprigan.identity_service.dto.request.UserCreationRequest;

@Mapper(componentModel = "spring")
public interface ProfileMapper {
    ProfileCreationRequest toProfileCreationRequest(UserCreationRequest request);
}
