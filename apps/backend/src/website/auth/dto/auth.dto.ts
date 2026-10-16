import {
  IsEmail,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class AuthDto {
  /** Phone number or email address */
  @IsString()
  @IsNotEmpty()
  @MaxLength(320)
  identifier: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  password: string;
}

export class RegisterDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  phone: string;

  @IsString()
  @IsEmail()
  @IsNotEmpty()
  @MaxLength(320)
  email: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(6)
  @MaxLength(512)
  password: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  lastName?: string;
}

export class ChangePasswordDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  oldPassword: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(6)
  @MaxLength(512)
  newPassword: string;
}
